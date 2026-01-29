///
/// @file src/h5gds.cu
/// @author Yohei MIKI (The University of Tokyo)
/// @brief parameter study related with VFD for GDS
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#include <H5FDgds.h>  // VFD for GDS
#include <hdf5.h>
#include <mpi.h>
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
#include <vector>                          // std::vector

#include "allocate.cuh"
#include "common.cuh"
#include "generate.cuh"
#include "hdf5.hpp"

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
auto main(int argc, char **argv) -> int32_t {
  // use scientific notation for floating-point number
  std::cout << std::scientific;

  MPI_Init(&argc, &argv);
  int mpi_rank;
  int mpi_size;
  MPI_Comm_rank(MPI_COMM_WORLD, &mpi_rank);
  MPI_Comm_size(MPI_COMM_WORLD, &mpi_size);

  // initialize the simulation
  // prepare options
  boost::program_options::options_description opt("List of options");
  opt.add_options()(
      "num", boost::program_options::value<type::idx>()->default_value(1024), "number of particles")(
      "cbuf", boost::program_options::value<size_t>()->default_value(CBSIZE_DEF), "copy buffer size (byte)")(
      "fblk", boost::program_options::value<size_t>()->default_value(FBSIZE_DEF), "file block size (byte)")(
      "memb", boost::program_options::value<size_t>()->default_value(MBOUNDARY_DEF), "memory boundary (byte)")(
      "skip", boost::program_options::bool_switch()->default_value(false), "skip consistency check between read and original data")(
      "asis", boost::program_options::bool_switch()->default_value(false), "read/write without hyperslab")(
      "virial", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(0.2), "Virial ratio of the system")(
      "radius", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "radius of the system")(
      "mass", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "total mass of the system")(
      "xdmf", boost::program_options::bool_switch()->default_value(false), "generate XDMF file to visualize the snapshot")(
      "output-path", boost::program_options::value<std::vector<std::string>>()->default_value({"dat"}, "dat")->composing(), "output path(s)")(
      "input-path", boost::program_options::value<std::string>(), "input path for read test")(
      "source-file", boost::program_options::value<std::vector<std::string>>()->composing(), "source HDF5 file(s) to load data from")(
      "help,h", "Help");
  // read input arguments
  boost::program_options::variables_map vm;
  boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opt), vm);
  boost::program_options::notify(vm);
  if (vm.count("help") == 1UL) {
    if (mpi_rank == 0) {
      std::cout << opt << std::endl;
    }
    MPI_Finalize();
    std::exit(EXIT_SUCCESS);
  }
  // configure the benchmark
  type::idx num = vm["num"].as<type::idx>();
  const auto cbuf = vm["cbuf"].as<size_t>();
  const auto fblk = vm["fblk"].as<size_t>();
  const auto memb = vm["memb"].as<size_t>();
  const auto virial = vm["virial"].as<decltype(newton)>();
  const auto radius = vm["radius"].as<decltype(newton)>();
  const auto mass = vm["mass"].as<decltype(newton)>();
  const auto skip = vm["skip"].as<bool>();
  const auto asis = vm["asis"].as<bool>();
  const auto write_xdmf = vm["xdmf"].as<bool>();
  const auto output_paths = vm["output-path"].as<std::vector<std::string>>();
  const std::string input_path = vm.count("input-path") ? vm["input-path"].as<std::string>() : "";
  const auto source_files = vm.count("source-file") ? vm["source-file"].as<std::vector<std::string>>() : std::vector<std::string>();
  vm.clear();

  if (!source_files.empty()) {
    const std::string source_file = source_files[static_cast<size_t>(mpi_rank) % source_files.size()];
    auto target_src = H5Fopen(source_file.c_str(), H5F_ACC_RDONLY, H5P_DEFAULT);
    if (target_src >= 0) {
      util::hdf5::read_attr(target_src, "num", &num);
      H5Fclose(target_src);
    } else {
      if (mpi_rank == 0) std::cerr << "ERROR: could not open source file " << source_file << std::endl;
      MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
      std::exit(EXIT_FAILURE);
    }
  }
  // copy buffer size must be a multiple of block size
  if ((cbuf % fblk) != 0U) {
    if (mpi_rank == 0) {
      std::cerr << "copy buffer size (" << cbuf << ") must be a multiple of block size (" << fblk << ")";
      std::cerr << std::endl;
      std::cerr << std::fflush;
    }
    MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    std::exit(EXIT_FAILURE);
  }

  // memory allocation
  int device_count;
  cudaGetDeviceCount(&device_count);
  cudaSetDevice(mpi_rank % device_count);
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH)
  type::idx *idx = nullptr;        // particle ID
  type::pos *pos = nullptr;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy = nullptr;  // velocity (x, y)
  type::vel_z *vel_z = nullptr;    // velocity (z)
#else                              //! defined(HOST_MALLOC_AND_FIRST_TOUCH)
  type::idx *idx;        // particle ID
  type::pos *pos;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy;  // velocity (x, y)
  type::vel_z *vel_z;  // velocity (z)
#endif                             //! defined(HOST_MALLOC_AND_FIRST_TOUCH)
  allocate_particles(&pos, &vel_xy, &vel_z, &idx, num);

  // initialize data on GPU
  if (source_files.empty()) {
    if (mpi_rank == 0) std::cout << "Generating data on GPU..." << std::endl;
    set_uniform_sphere(num, pos, vel_xy, vel_z, idx, mass, radius, virial, newton);
  } else {
    const std::string source_file = source_files[static_cast<size_t>(mpi_rank) % source_files.size()];
    if (mpi_rank == 0) std::cout << "Loading data from " << source_file << "..." << std::endl;

    util::hdf5::create_h5t_real2();
    util::hdf5::create_h5t_real4();
    const auto [hdf5_dataspace_Nx3, hdf5_dataspace_Nx2, hdf5_dataspace_Nx1, hdf5_dataspace_Nx2_3, hdf5_dataspace_Nx1_3, hdf5_dataspace_Nx4, hdf5_dataspace_Nx3_4, hdf5_dataspace_Nx1_4] = util::hdf5::prepare_hyperslab_Nx3(num);

    auto h5load = util::hdf5::h5multi_read{};
    h5load.allocate(5);
    auto target_src = H5Fopen(source_file.c_str(), H5F_ACC_RDONLY, H5P_DEFAULT);

    h5load.commit(target_src, "id", util::hdf5::h5type(*idx), idx);
    const auto FPtype = util::hdf5::h5type(*vel_z);
    if (!asis) {
      h5load.commit(target_src, "velocity", FPtype, vel_xy, hdf5_dataspace_Nx2, hdf5_dataspace_Nx2_3);
      h5load.commit(vel_z, h5load.get_last_dataset(), FPtype, hdf5_dataspace_Nx1, hdf5_dataspace_Nx1_3);
      h5load.commit(target_src, "position", FPtype, pos, hdf5_dataspace_Nx3_4, hdf5_dataspace_Nx3);
      h5load.commit(target_src, "mass", FPtype, pos, hdf5_dataspace_Nx1_4, hdf5_dataspace_Nx1);
    } else {
      h5load.commit(target_src, "pos", util::hdf5::h5type(*pos), pos);
      h5load.commit(target_src, "vel_xy", util::hdf5::h5type(*vel_xy), vel_xy);
      h5load.commit(target_src, "vel_z", util::hdf5::h5type(*vel_z), vel_z);
    }
    h5load.execute();
    H5Fclose(target_src);

    util::hdf5::close_dataspace(hdf5_dataspace_Nx1_3);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx2_3);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx1);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx2);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx3);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx1_4);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx3_4);
    util::hdf5::close_dataspace(hdf5_dataspace_Nx4);
    util::hdf5::remove_h5t_real2();
    util::hdf5::remove_h5t_real4();
  }

  if (mpi_rank == 0) std::cout << "Setup complete. Starting benchmarks..." << std::endl;

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

  // prepare dataspaces for HDF5
  util::hdf5::create_h5t_real2();
  util::hdf5::create_h5t_real4();
  const auto hdf5_dataspace_N = util::hdf5::setup_dataspace(num);
  const auto hdf5_dataspace_1 = util::hdf5::setup_dataspace();
  const auto [hdf5_dataspace_Nx3, hdf5_dataspace_Nx2, hdf5_dataspace_Nx1, hdf5_dataspace_Nx2_3, hdf5_dataspace_Nx1_3, hdf5_dataspace_Nx4, hdf5_dataspace_Nx3_4, hdf5_dataspace_Nx1_4] = util::hdf5::prepare_hyperslab_Nx3(num);
  auto h5write = util::hdf5::h5multi_write{};
  auto h5read = util::hdf5::h5multi_read{};
  h5write.allocate(5);  // idx, position (x, y, z), velocity (x, y), velocity (z), and mass
  h5read.allocate(5);   // idx, position (x, y, z), velocity (x, y), velocity (z), and mass

  // prepare to use GPUDirect Storage via HDF5 with VFD
  auto fapl = H5Pcreate(H5P_FILE_ACCESS);
  H5Pset_fapl_gds(fapl, memb, fblk, cbuf);

  // create HDF5 file
  boost::uuids::uuid uuid;
  if (mpi_rank == 0) {
    uuid = boost::uuids::random_generator{}();
  }
  MPI_Bcast(&uuid, sizeof(uuid), MPI_BYTE, 0, MPI_COMM_WORLD);

  const auto series = boost::lexical_cast<std::string>(uuid);
  const std::string output_path = output_paths[static_cast<size_t>(mpi_rank) % output_paths.size()];
  auto name = output_path + "/" + series + "_rank" + std::to_string(mpi_rank) + ".h5";
  auto target = H5Fcreate(name.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, fapl);
  // preparation for H5Dwrite_multi()
  h5write.commit(hdf5_dataspace_N, target, "id", util::hdf5::h5type(*idx), idx);
  const auto FPtype = util::hdf5::h5type(*vel_z);
  if (!asis) {
    h5write.commit(hdf5_dataspace_Nx3, target, "velocity", FPtype, vel_xy, hdf5_dataspace_Nx2, hdf5_dataspace_Nx2_3);
    h5write.commit(vel_z, h5write.get_last_dataset(), FPtype, hdf5_dataspace_Nx1, hdf5_dataspace_Nx1_3);
    h5write.commit(hdf5_dataspace_Nx3, target, "position", FPtype, pos, hdf5_dataspace_Nx3_4, hdf5_dataspace_Nx3);
    h5write.commit(hdf5_dataspace_Nx1, target, "mass", FPtype, pos, hdf5_dataspace_Nx1_4, hdf5_dataspace_Nx1);
  } else {
    h5write.commit(hdf5_dataspace_N, target, "pos", util::hdf5::h5type(*pos), pos);
    h5write.commit(hdf5_dataspace_N, target, "vel_xy", util::hdf5::h5type(*vel_xy), vel_xy);
    h5write.commit(hdf5_dataspace_N, target, "vel_z", util::hdf5::h5type(*vel_z), vel_z);
  }
  // execute H5Dwrite_multi()
  // h5write.execute();
  MPI_Barrier(MPI_COMM_WORLD);
  const auto elapse_write = benchmark([&h5write]() { h5write.execute(); });
  // write attribute
  util::hdf5::write_attr(hdf5_dataspace_1, target, "num", &num);
  // close the file
  H5Fclose(target);

  // generate XDMF file if requested
  if (!asis && write_xdmf) {
    auto xdmf_name = output_path + "/" + series + "_rank" + std::to_string(mpi_rank) + ".xdmf";
    std::ofstream xml(xdmf_name, std::ios::out);

    xml << R"(<?xml version="1.0" ?>)" << std::endl;
    xml << R"(<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>)" << std::endl;
    xml << R"(<Xdmf Version="3.0">)" << std::endl;
    xml << "  <Domain>" << std::endl;
    xml << R"(    <Grid Name="particle" GridType="Uniform">)" << std::endl;
    xml << R"(      <Topology TopologyType="Polyvertex" NumberOfElements=")" << num << R"("/>)" << std::endl;

    xml << R"(      <Geometry GeometryType="XYZ">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"( 3" NumberType="Float" Precision=")" << sizeof(decltype(*vel_z)) << R"(" Format="HDF">)" << std::endl;
    xml << "          " << series + "_rank" + std::to_string(mpi_rank) + ".h5"
        << ":/"
        << "position" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Geometry>" << std::endl;

    xml << R"(      <Attribute Name="velocity" AttributeType="Vector" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"( 3" NumberType="Float" Precision=")" << sizeof(decltype(*vel_z)) << R"(" Format="HDF">)" << std::endl;
    xml << "          " << series + "_rank" + std::to_string(mpi_rank) + ".h5"
        << ":/"
        << "velocity" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << R"(      <Attribute Name="mass" AttributeType="Scalar" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"(" NumberType="Float" Precision=")" << sizeof(decltype(*vel_z)) << R"(" Format="HDF">)" << std::endl;
    xml << "          " << series + "_rank" + std::to_string(mpi_rank) + ".h5"
        << ":/"
        << "mass" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << R"(      <Attribute Name="ID" AttributeType="Scalar" Center="Node">)" << std::endl;
    xml << R"(        <DataItem Dimensions=")" << num << R"(" NumberType="UInt" Precision=")" << sizeof(decltype(*idx)) << R"(" Format="HDF">)" << std::endl;
    xml << "          " << series + "_rank" + std::to_string(mpi_rank) + ".h5"
        << ":/"
        << "id" << std::endl;
    xml << "        </DataItem>" << std::endl;
    xml << "      </Attribute>" << std::endl;

    xml << "    </Grid>" << std::endl;
    xml << "  </Domain>" << std::endl;
    xml << "</Xdmf>" << std::endl;
    xml.close();
  }

  // read the file and compare
  const std::string read_name = input_path.empty() ? name : input_path;
  target = H5Fopen(read_name.c_str(), H5F_ACC_RDONLY, fapl);
  auto num_read = std::remove_const_t<decltype(num)>{};
  util::hdf5::read_attr(target, "num", &num_read);
  if (num_read != num) {
    std::cerr << "rank " << mpi_rank << ": " << __FILE__ << "(" << __LINE__ << "): " << __func__ << ": ERROR: num_read (" << num_read << ") does not match with num (" << num << ")" << std::endl
              << std::flush;
    MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    std::exit(EXIT_FAILURE);
  }
  std::remove_reference_t<decltype(*idx)> *idx_read = nullptr;        // particle ID
  std::remove_reference_t<decltype(*pos)> *pos_read = nullptr;        // position (x, y, z) and mass (w)
  std::remove_reference_t<decltype(*vel_xy)> *vel_xy_read = nullptr;  // velocity (x, y)
  std::remove_reference_t<decltype(*vel_z)> *vel_z_read = nullptr;    // velocity (z)
  allocate_particles(&pos_read, &vel_xy_read, &vel_z_read, &idx_read, num_read);
  // preparation for H5Dread_multi()
  h5read.commit(target, "id", util::hdf5::h5type(*idx_read), idx_read);
  const auto FPtype_read = util::hdf5::h5type(*vel_z_read);
  if (!asis) {
    h5read.commit(target, "velocity", FPtype_read, vel_xy_read, hdf5_dataspace_Nx2, hdf5_dataspace_Nx2_3);
    h5read.commit(vel_z_read, h5read.get_last_dataset(), FPtype_read, hdf5_dataspace_Nx1, hdf5_dataspace_Nx1_3);
    h5read.commit(target, "position", FPtype_read, pos_read, hdf5_dataspace_Nx3_4, hdf5_dataspace_Nx3);
    h5read.commit(target, "mass", FPtype_read, pos_read, hdf5_dataspace_Nx1_4, hdf5_dataspace_Nx1);
  } else {
    h5read.commit(target, "pos", util::hdf5::h5type(*pos_read), pos_read);
    h5read.commit(target, "vel_xy", util::hdf5::h5type(*vel_xy_read), vel_xy_read);
    h5read.commit(target, "vel_z", util::hdf5::h5type(*vel_z_read), vel_z_read);
  }
  // execute H5Dread_multi()
  // h5read.execute();
  MPI_Barrier(MPI_COMM_WORLD);
  const auto elapse_read = benchmark([&h5read]() { h5read.execute(); });

  // close the file
  H5Fclose(target);
  H5Pclose(fapl);

  util::hdf5::close_dataspace(hdf5_dataspace_N);
  util::hdf5::close_dataspace(hdf5_dataspace_1);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx1_3);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx2_3);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx1);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx2);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx3);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx1_4);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx3_4);
  util::hdf5::close_dataspace(hdf5_dataspace_Nx4);
  util::hdf5::remove_h5t_real2();
  util::hdf5::remove_h5t_real4();

  // check the read results
  const auto success = skip ? true : (thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)idx, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)(idx + num), (thrust::device_ptr<std::remove_reference_t<decltype(*idx_read)>>)idx_read) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)pos, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)(pos + num), (thrust::device_ptr<std::remove_reference_t<decltype(*pos_read)>>)pos_read, compare_pos()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)vel_xy, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)(vel_xy + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy_read)>>)vel_xy_read, compare_vel_xy()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)vel_z, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)(vel_z + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z_read)>>)vel_z_read));

  if (success) {
    // output the benchmark result
    const std::string report = "log/h5gds_benchmark.csv";
    if (mpi_rank == 0) {
      const boost::filesystem::path previous(report);
      boost::system::error_code err;
      if (!boost::filesystem::exists(previous, err) || err) {
        std::ofstream output(report, std::ios::app);
        output << "rank,N,data size [byte],copy buffer size [byte],file block size [byte],memory boundary [byte],latency (write) [s],latency (read) [s],bandwidth (write) [byte/s],bandwidth (read) [byte/s],filename" << std::endl;
      }
    }
    MPI_Barrier(MPI_COMM_WORLD);

    // write statistics of the simulation
    std::ofstream output(report, std::ios::app);
    output << std::scientific;
    output << mpi_rank << "," << num;
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

    // Aggregate results on rank 0
    double max_elapse_write, max_elapse_read;
    MPI_Reduce(&elapse_write, &max_elapse_write, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&elapse_read, &max_elapse_read, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    double total_datasize;
    MPI_Reduce(&datasize, &total_datasize, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);

    if (mpi_rank == 0) {
      std::cout << "--- Aggregated Results (" << mpi_size << " ranks) ---" << std::endl;
      std::cout << "Total Data Size:  " << total_datasize << " bytes" << std::endl;
      std::cout << "Max Write Latency: " << max_elapse_write << " s" << std::endl;
      std::cout << "Max Read Latency:  " << max_elapse_read << " s" << std::endl;
      std::cout << "Aggregated Write Bandwidth: " << total_datasize / max_elapse_write << " bytes/s" << std::endl;
      std::cout << "Aggregated Read Bandwidth:  " << total_datasize / max_elapse_read << " bytes/s" << std::endl;
    }
  } else {
    std::cerr << "rank " << mpi_rank << ": " << __FILE__ << "(" << __LINE__ << "): " << __func__ << ": ERROR: read data does not match with the original data" << std::endl
              << std::flush;
    MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    std::exit(EXIT_FAILURE);
  }

  release_particles(pos, vel_xy, vel_z, idx);
  release_particles(pos_read, vel_xy_read, vel_z_read, idx_read);

  MPI_Finalize();
  std::exit(EXIT_SUCCESS);
}
