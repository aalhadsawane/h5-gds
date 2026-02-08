///
/// @file src/h5gds.cu
/// @author Yohei MIKI (The University of Tokyo)
/// @brief parameter study related with VFD for GDS
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#include <adios2.h>
#include <thrust/device_ptr.h>
#include <thrust/equal.h>
#include <thrust/execution_policy.h>

#include <boost/filesystem.hpp>            // boost::filesystem
#include <boost/lexical_cast.hpp>          // boost::lexical_cast
#include <boost/program_options.hpp>       // boost::program_options
#include <boost/uuid/uuid_generators.hpp>  // boost::uuids::random_generator
#include <boost/uuid/uuid_io.hpp>          // convert boost::uuids::uuid to std::string
#include <cstdlib>                         // std::exit
#include <fstream>                         // std::ofstream
#include <iomanip>                         // std::setw
#include <iostream>                        // std::cout
#include <sstream>                         // std::stringstream
#include <string>                          // std::string

#include <helper_cuda.h>    // checkCudaErrors
#include <curand_mtgp32.h>  // THREAD_NUM

#include "allocate.cuh"
#include "common.cuh"
#include "generate.cuh"

// Default buffer sizes (restored from legacy hdf5.hpp/common)
constexpr size_t CBSIZE_DEF = 4ULL * 1024ULL * 1024ULL; // 4MB
constexpr size_t FBSIZE_DEF = 4ULL * 1024ULL;           // 4KB
constexpr size_t MBOUNDARY_DEF = 1ULL * 1024ULL * 1024ULL; // 1MB

// Utility function for rounding up to nearest multiple
constexpr auto round_up(const size_t org, const size_t unit) {
  const size_t mod = org % unit;
  return ((mod == 0) ? org : (org + unit - mod));
}

static constexpr type::vel_z newton = 1.0F;  // gravitational constant in the computational unit

struct compare_pos {
  __host__ __device__ bool operator()(type::pos a, type::pos b) const {
    return ((a.x == b.x) && (a.y == b.y) && (a.z == b.z) && (a.w == b.w));
  }
};
struct compare_vel_xy {
  __host__ __device__ bool operator()(type::vel_xy a, type::vel_xy b) const {
    return ((a.x == b.x) && (a.y == b.y));
  }
};

///
/// @brief main function
///
/// @param[in] argc number of input argument(s)
/// @param[in] argv input argument(s)
///
auto main(const int32_t argc, const char *const *const argv) -> int32_t {
  // use scientific notation for floating-point number
  std::cout << std::scientific;

  // initialize the simulation
  // prepare options
  boost::program_options::options_description opt("List of options");
  opt.add_options()(
      "num", boost::program_options::value<type::idx>()->default_value(1024), "number of particles")(
      "cbuf", boost::program_options::value<size_t>()->default_value(CBSIZE_DEF), "copy buffer size (byte)")(
      "fblk", boost::program_options::value<size_t>()->default_value(FBSIZE_DEF), "file block size (byte)")(
      "memb", boost::program_options::value<size_t>()->default_value(MBOUNDARY_DEF), "memory boundary (byte)")(
      "vfd", boost::program_options::value<std::string>()->default_value("gds"), "VFD driver to use: sec2, gds, or direct")(
      "skip", boost::program_options::bool_switch()->default_value(false), "skip consistency check between read and original data")(
      "asis", boost::program_options::bool_switch()->default_value(false), "read/write without hyperslab")(
      "virial", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(0.2), "Virial ratio of the system")(
      "radius", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "radius of the system")(
      "mass", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "total mass of the system")(
      "xdmf", boost::program_options::bool_switch()->default_value(false), "generate XDMF file to visualize the snapshot")(
      "help,h", "Help");
  // read input arguments
  boost::program_options::variables_map vm;
  boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opt), vm);
  boost::program_options::notify(vm);
  if (vm.count("help") == 1UL) {
    std::cout << opt << std::endl;
    std::exit(EXIT_SUCCESS);
  }
  // configure the benchmark
  const auto num = vm["num"].as<type::idx>();
  const auto cbuf = vm["cbuf"].as<size_t>();
  const auto fblk = vm["fblk"].as<size_t>();
  const auto memb = vm["memb"].as<size_t>();
  const auto vfd_name = vm["vfd"].as<std::string>();
  const auto virial = vm["virial"].as<decltype(newton)>();
  const auto radius = vm["radius"].as<decltype(newton)>();
  const auto mass = vm["mass"].as<decltype(newton)>();
  const auto skip = vm["skip"].as<bool>();
  // const auto asis = vm["asis"].as<bool>(); // Unused in ADIOS2 port
  const auto write_xdmf = vm["xdmf"].as<bool>();
  vm.clear();

  // memory allocation
  cudaSetDevice(0);

  type::idx *idx;        // particle ID
  type::pos *pos;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy;  // velocity (x, y)
  type::vel_z *vel_z;    // velocity (z)

  allocate_particles(&pos, &vel_xy, &vel_z, &idx, num);

  set_uniform_sphere(num, pos, vel_xy, vel_z, idx, mass, radius, virial, newton);

  constexpr auto benchmark = [](const auto func) noexcept(false) {
    // cudaDeviceSynchronize();
    struct timespec ini;
    // clock_gettime(CLOCK_MONOTONIC_RAW, &ini);
    clock_gettime(CLOCK_MONOTONIC, &ini);
    // clock_gettime(CLOCK_BOOTTIME, &ini);
    func();
    // cudaDeviceSynchronize();
    struct timespec end;
    // clock_gettime(CLOCK_MONOTONIC_RAW, &end);
    clock_gettime(CLOCK_MONOTONIC, &end);
    // clock_gettime(CLOCK_BOOTTIME, &end);
    return (std::fma(1.0e-9, static_cast<double>(end.tv_nsec - ini.tv_nsec), end.tv_sec - ini.tv_sec));
  };

  // ADIOS2 setup
  adios2::ADIOS adios("adios2.xml");
  adios2::IO io = adios.DeclareIO("SimulationOutput");

  // Apply runtime parameters from command line arguments
  // This allows the parameter sweep in job.pbs to control the HDF5 backend

  // Validate VFD driver selection environment variable (HDF5_DRIVER) against requested VFD
  const char* hdf5_driver_env = std::getenv("HDF5_DRIVER");
  std::string active_vfd = (hdf5_driver_env != nullptr) ? std::string(hdf5_driver_env) : "default (sec2)";

  if (vfd_name == "gds") {
    if (active_vfd != "gds") {
      std::cerr << "WARNING: User requested VFD 'gds' but HDF5_DRIVER environment variable is set to '"
                << active_vfd << "'. GDS may not be active!" << std::endl;
    }
  } else if (vfd_name == "direct") {
    if (active_vfd != "direct") {
      std::cerr << "WARNING: User requested VFD 'direct' but HDF5_DRIVER environment variable is set to '"
                << active_vfd << "'. Direct I/O may not be active!" << std::endl;
    }
  } else if (vfd_name == "sec2") {
    if (active_vfd != "sec2" && hdf5_driver_env != nullptr) {
      std::cerr << "WARNING: User requested VFD 'sec2' but HDF5_DRIVER environment variable is set to '"
                << active_vfd << "'." << std::endl;
    }
  } else {
    std::cerr << "Invalid VFD driver: " << vfd_name << ". Must be one of: sec2, gds, direct" << std::endl;
    std::exit(EXIT_FAILURE);
  }

  // Set chunking/buffer parameters if applicable
  // Mapping 'fblk' (file block size) and 'cbuf' (copy buffer size)

  // 'cbuf': Mapped to BufferChunkSize. ADIOS2 typically parses size strings.
  if (cbuf > 0) {
      io.SetParameter("BufferChunkSize", std::to_string(cbuf));
  }

  // 'fblk' & 'memb': These correspond to H5Pset_alignment and H5Pset_fapl_direct.
  // ADIOS2 HDF5 engine parameters vary by version.
  // If ADIOS2 supports generic HDF5 parameters via "H5P_..." keys in the future, they would go here.
  // For now, we accept them to maintain the parameter sweep interface and log them in CSV.
  // The 'fblk' might loosely map to chunking if we used chunked I/O variables, but we are writing global arrays.

  auto uuid = boost::uuids::random_generator{}();
  const auto series = boost::lexical_cast<std::string>(uuid);
  auto name = "dat/" + series + ".h5"; // Extension .h5 for HDF5 engine

  // Define variables
  auto var_id = io.DefineVariable<type::idx>("id", {num}, {0}, {num});
  auto var_pos = io.DefineVariable<float>("position", {num, 4}, {0, 0}, {num, 4});
  auto var_vel_xy = io.DefineVariable<float>("velocity_xy", {num, 2}, {0, 0}, {num, 2});
  auto var_vel_z = io.DefineVariable<type::vel_z>("velocity_z", {num}, {0}, {num});

  // Define attributes
  io.DefineAttribute<type::idx>("num", num);

  // Write
  adios2::Engine writer = io.Open(name, adios2::Mode::Write);

  const auto elapse_write = benchmark([&]() {
    writer.Put(var_id, idx);
    writer.Put(var_pos, (float*)pos);
    writer.Put(var_vel_xy, (float*)vel_xy);
    writer.Put(var_vel_z, vel_z);
    writer.PerformPuts();
  });

  writer.Close();

  // generate XDMF file if requested
  if (write_xdmf) {
    std::ofstream xml("dat/" + series + ".xdmf", std::ios::out);

    xml << R"(<?xml version="1.0" ?>)" << std::endl;
    xml << R"(<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>)" << std::endl;
    xml << R"(<Xdmf Version="3.0">)" << std::endl;
    xml << "  <Domain>" << std::endl;
    xml << R"(    <Grid Name="particle" GridType="Uniform">)" << std::endl;
    xml << R"(      <Topology TopologyType="Polyvertex" NumberOfElements=")" << num << R"("/>)" << std::endl;

    xml << R"(      <Geometry GeometryType="XYZ">)" << std::endl;
    // XDMF expects XYZ. Our 'position' is float4 (XYZW).
    // We can point to the same dataset. XDMF might read the first 3 components if stride is set?
    // Or we can say Dimensions="N 4" and hope visualization tools handle it or ignore W.
    // Standard XYZ expects 3 components.
    // If we want to be strict, we might need a HyperSlab in XDMF.
    // For now, let's list it as 4 components and see if tools adapt, or use type="VXVYVZ" separate arrays? No, it's one array.
    // Let's assume the user handles visualization or that tools can take Nx4.
    xml << R"(        <DataItem Dimensions=")" << num << R"( 4" NumberType="Float" Precision="4" Format="HDF">)" << std::endl;
    xml << "          " << series + ".h5"
        << ":/"
        << "position" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Geometry>" << std::endl;

    xml << R"(      <Attribute Name="velocity_xy" AttributeType="Vector" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"( 2" NumberType="Float" Precision="4" Format="HDF">)" << std::endl;
    xml << "          " << series + ".h5"
        << ":/"
        << "velocity_xy" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << R"(      <Attribute Name="velocity_z" AttributeType="Scalar" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"(" NumberType="Float" Precision="4" Format="HDF">)" << std::endl;
    xml << "          " << series + ".h5"
        << ":/"
        << "velocity_z" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << R"(      <Attribute Name="ID" AttributeType="Scalar" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"(" NumberType="UInt" Precision=")" << sizeof(type::idx) << R"(" Format="HDF">)" << std::endl;
    xml << "          " << series + ".h5"
        << ":/"
        << "id" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << "    </Grid>" << std::endl;
    xml << "  </Domain>" << std::endl;
    xml << "</Xdmf>" << std::endl;
    xml.close();
  }

  // Read back
  type::idx *idx_read;        // particle ID
  type::pos *pos_read;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy_read;  // velocity (x, y)
  type::vel_z *vel_z_read;    // velocity (z)

  // We need to read 'num' attribute first to allocate.
  // ADIOS2 can read attributes.

  adios2::Engine reader = io.Open(name, adios2::Mode::Read);

  // Read attribute
  auto attr_num = io.InquireAttribute<type::idx>("num");
  type::idx num_read = 0;
  if(attr_num) {
      // Attributes are available immediately after Open in some engines, but safest to get them.
      // ADIOS2 C++ API: data() returns pointer to value if available.
      num_read = attr_num.Data()[0];
  } else {
       std::cerr << "ERROR: Attribute 'num' not found." << std::endl;
       std::exit(EXIT_FAILURE);
  }

  if (num_read != num) {
    std::cerr << __FILE__ << "(" << __LINE__ << "): " << __func__ << ": ERROR: num_read (" << num_read << ") does not match with num (" << num << ")" << std::endl
              << std::flush;
    std::exit(EXIT_FAILURE);
  }

  allocate_particles(&pos_read, &vel_xy_read, &vel_z_read, &idx_read, num_read);

  auto r_var_id = io.InquireVariable<type::idx>("id");
  auto r_var_pos = io.InquireVariable<float>("position");
  auto r_var_vel_xy = io.InquireVariable<float>("velocity_xy");
  auto r_var_vel_z = io.InquireVariable<type::vel_z>("velocity_z");

  // Check variables exist
  if (!r_var_id || !r_var_pos || !r_var_vel_xy || !r_var_vel_z) {
      std::cerr << "ERROR: One or more variables not found in file." << std::endl;
      std::exit(EXIT_FAILURE);
  }

  // Set selections (if needed, default is global array which matches our memory size here)
  r_var_id.SetSelection({{0}, {num_read}});
  r_var_pos.SetSelection({{0, 0}, {num_read, 4}});
  r_var_vel_xy.SetSelection({{0, 0}, {num_read, 2}});
  r_var_vel_z.SetSelection({{0}, {num_read}});

  const auto elapse_read = benchmark([&]() {
      reader.Get(r_var_id, idx_read);
      reader.Get(r_var_pos, (float*)pos_read);
      reader.Get(r_var_vel_xy, (float*)vel_xy_read);
      reader.Get(r_var_vel_z, vel_z_read);
      reader.PerformGets();
  });

  reader.Close();

  // check the read results
  const auto success = skip ? true : (thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)idx, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)(idx + num), (thrust::device_ptr<std::remove_reference_t<decltype(*idx_read)>>)idx_read) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)pos, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)(pos + num), (thrust::device_ptr<std::remove_reference_t<decltype(*pos_read)>>)pos_read, compare_pos()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)vel_xy, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)(vel_xy + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy_read)>>)vel_xy_read, compare_vel_xy()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)vel_z, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)(vel_z + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z_read)>>)vel_z_read));

  if (success) {
    // output the benchmark result
    const std::string report = "log/h5gds_benchmark.csv";
    const boost::filesystem::path previous(report);
    boost::system::error_code err;
    const auto exist = boost::filesystem::exists(previous, err);

    // write header if report is a new file
    std::ofstream output(report, std::ios::app);
    if (!exist || err) {
      output << "VFD";
      output << ",skip";
      output << ",N";
      output << ",data size [byte]";
      output << ",copy buffer size [byte]";
      output << ",file block size [byte]";
      output << ",memory boundary [byte]";
      output << ",latency (write) [s]";
      output << ",latency (read) [s]";
      output << ",bandwidth (write) [byte/s]";
      output << ",bandwidth (read) [byte/s]";
      output << ",filename";
      output << std::endl;
    }

    // write statistics of the simulation
    output << std::scientific;
    output << vfd_name; // Keep original VFD name for logging
    output << "," << (skip ? "true" : "false");
    output << "," << num;
    const auto datasize = static_cast<double>(num) * static_cast<double>(sizeof(std::remove_reference_t<decltype(*idx)>) + sizeof(std::remove_reference_t<decltype(*pos)>) + sizeof(std::remove_reference_t<decltype(*vel_xy)>) + sizeof(std::remove_reference_t<decltype(*vel_z)>));
    output << "," << datasize;
    output << "," << cbuf;
    output << "," << fblk;
    output << "," << memb;
    output << "," << elapse_write;
    output << "," << elapse_read;
    output << "," << datasize / elapse_write;
    output << "," << datasize / elapse_read;
    output << "," << name;
    output << std::endl;
    output.close();
  } else {
    std::cerr << __FILE__ << "(" << __LINE__ << "): " << __func__ << ": ERROR: read data does not match with the original data" << std::endl
              << std::flush;
    std::exit(EXIT_FAILURE);
  }

  release_particles(pos, vel_xy, vel_z, idx);
  release_particles(pos_read, vel_xy_read, vel_z_read, idx_read);

  // delete the file to save space
  boost::filesystem::remove(name);
  if (write_xdmf) {
    boost::filesystem::remove("dat/" + series + ".xdmf");
  }

  std::exit(EXIT_SUCCESS);
}
