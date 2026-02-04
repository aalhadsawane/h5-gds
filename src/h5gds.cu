///
/// @file src/h5gds.cu
/// @author Yohei MIKI (The University of Tokyo)
/// @brief parameter study related with VFD for GDS (Ported to ADIOS2)
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#include <adios2.h>
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

#define MIYABI_CORES_PER_NODE 72

#include "allocate.cuh"
#include "common.cuh"
#include "generate.cuh"

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

  // Dynamic topology detection for robust GPU assignment
  MPI_Comm node_comm;
  MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, mpi_rank, MPI_INFO_NULL, &node_comm);
  int local_rank;
  MPI_Comm_rank(node_comm, &local_rank);
  MPI_Comm_free(&node_comm);

  const int node_id = mpi_rank / MIYABI_CORES_PER_NODE;

  // Initialize ADIOS2
  // We use MPI_COMM_SELF to treat each rank as an independent writer/reader,
  // preserving the "file-per-rank" structure of the original code which enables local storage benchmarking.
  adios2::ADIOS ad("adios2_config.xml", MPI_COMM_SELF);

  // initialize the simulation
  // prepare options
  boost::program_options::options_description opt("List of options");
  opt.add_options()(
      "num", boost::program_options::value<type::idx>()->default_value(1024), "number of particles")(
      "skip", boost::program_options::bool_switch()->default_value(false), "skip consistency check between read and original data")(
      "virial", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(0.2), "Virial ratio of the system")(
      "radius", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "radius of the system")(
      "mass", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "total mass of the system")(
      "output-path", boost::program_options::value<std::vector<std::string>>()->default_value({"dat"}, "dat")->composing(), "output path(s)")(
      "input-path", boost::program_options::value<std::vector<std::string>>()->composing(), "input path(s) for read test")(
      "source-file", boost::program_options::value<std::vector<std::string>>()->composing(), "source file(s) to load data from")(
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
  const auto skip = vm["skip"].as<bool>();
  const auto virial = vm["virial"].as<decltype(newton)>();
  const auto radius = vm["radius"].as<decltype(newton)>();
  const auto mass = vm["mass"].as<decltype(newton)>();
  const auto output_paths = vm["output-path"].as<std::vector<std::string>>();
  const auto input_paths = vm.count("input-path") ? vm["input-path"].as<std::vector<std::string>>() : std::vector<std::string>();
  const auto source_files = vm.count("source-file") ? vm["source-file"].as<std::vector<std::string>>() : std::vector<std::string>();
  vm.clear();

  if (!source_files.empty()) {
    const std::string source_file = source_files[static_cast<size_t>(mpi_rank) % source_files.size()];
    try {
      adios2::IO io_src = ad.DeclareIO("SourceInput");
      adios2::Engine reader = io_src.Open(source_file, adios2::Mode::Read);
      auto attr_num = io_src.InquireAttribute<type::idx>("num");
      if (attr_num) {
          num = attr_num.Data()[0];
      }
      reader.Close();
      ad.RemoveIO("SourceInput");
    } catch (std::exception &e) {
      if (mpi_rank == 0) std::cerr << "ERROR: could not open source file " << source_file << ": " << e.what() << std::endl;
      MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
      std::exit(EXIT_FAILURE);
    }
  }

  // memory allocation
  int device_count;
  cudaGetDeviceCount(&device_count);
  cudaSetDevice(local_rank % device_count);

  if (mpi_rank == 0) {
    std::cout << "Miyabi Cluster Configuration: " << MIYABI_CORES_PER_NODE << " cores/node" << std::endl;
  }
  std::cout << "Rank " << mpi_rank << " assigned to Node " << node_id << ", Local Rank " << local_rank << ", GPU " << (local_rank % device_count) << std::endl;

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

    adios2::IO io_src = ad.DeclareIO("SourceLoad");
    adios2::Engine reader = io_src.Open(source_file, adios2::Mode::Read);

    // Inquire variables
    auto var_id = io_src.InquireVariable<type::idx>("id");
    auto var_pos = io_src.InquireVariable<float>("pos_mass");
    auto var_vxy = io_src.InquireVariable<float>("vel_xy");
    auto var_vz = io_src.InquireVariable<float>("vel_z");

    if (var_id && var_pos && var_vxy && var_vz) {
        // Set selection (read all)
        var_id.SetSelection({{0}, {num}});
        var_pos.SetSelection({{0, 0}, {num, 4}});
        var_vxy.SetSelection({{0, 0}, {num, 2}});
        var_vz.SetSelection({{0}, {num}});

        // Get data (ADIOS2 handles GPU memory if pointer is device)
        reader.Get(var_id, idx);
        reader.Get(var_pos, reinterpret_cast<float*>(pos));
        reader.Get(var_vxy, reinterpret_cast<float*>(vel_xy));
        reader.Get(var_vz, vel_z);
        reader.PerformGets();
    } else {
        std::cerr << "Rank " << mpi_rank << ": Error: Missing variables in source file." << std::endl;
        MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    }
    reader.Close();
    ad.RemoveIO("SourceLoad");
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

  // Setup ADIOS2 for writing
  adios2::IO io_out = ad.DeclareIO("SimulationOutput");

  // Define variables
  // Since we use independent files (MPI_COMM_SELF), shape is {num}.
  auto var_id = io_out.DefineVariable<type::idx>("id", {num}, {0}, {num});
  auto var_pos = io_out.DefineVariable<float>("pos_mass", {num, 4}, {0, 0}, {num, 4});
  auto var_vxy = io_out.DefineVariable<float>("vel_xy", {num, 2}, {0, 0}, {num, 2});
  auto var_vz = io_out.DefineVariable<float>("vel_z", {num}, {0}, {num});

  io_out.DefineAttribute<type::idx>("num", num);

  // create filename
  boost::uuids::uuid uuid;
  if (mpi_rank == 0) {
    uuid = boost::uuids::random_generator{}();
  }
  MPI_Bcast(&uuid, sizeof(uuid), MPI_BYTE, 0, MPI_COMM_WORLD);

  const auto series = boost::lexical_cast<std::string>(uuid);
  const std::string output_path = output_paths[static_cast<size_t>(mpi_rank) % output_paths.size()];

  // Ensure output directory exists
  boost::filesystem::path dir(output_path);
  if (!boost::filesystem::exists(dir)) {
    if (mpi_rank == 0) {
      std::cout << "Directory " << output_path << " does not exist. Creating it..." << std::endl;
    }
    boost::system::error_code ec;
    if (!boost::filesystem::create_directories(dir, ec)) {
       // Proceeding might fail, but let IO handle it
    }
  }
  MPI_Barrier(MPI_COMM_WORLD);

  auto name = output_path + "/" + series + "_rank" + std::to_string(mpi_rank) + ".h5";

  // execute write benchmark
  double elapse_write = 0.0;

  {
      elapse_write = benchmark([&]() {
        adios2::Engine writer = io_out.Open(name, adios2::Mode::Write);
        writer.BeginStep();
        writer.Put(var_id, idx);
        writer.Put(var_pos, reinterpret_cast<float*>(pos));
        writer.Put(var_vxy, reinterpret_cast<float*>(vel_xy));
        writer.Put(var_vz, vel_z);
        writer.EndStep();
        writer.Close();
      });
  }

  // read the file and compare
  const std::string read_name = input_paths.empty() ? name : input_paths[static_cast<size_t>(mpi_rank) % input_paths.size()];

  type::idx num_read = 0;

  std::remove_reference_t<decltype(*idx)> *idx_read = nullptr;
  std::remove_reference_t<decltype(*pos)> *pos_read = nullptr;
  std::remove_reference_t<decltype(*vel_xy)> *vel_xy_read = nullptr;
  std::remove_reference_t<decltype(*vel_z)> *vel_z_read = nullptr;

  double elapse_read = 0.0;

  // Use a separate IO for reading to avoid conflict or just reuse logical name?
  // Use new IO name for safety.
  adios2::IO io_in = ad.DeclareIO("SimulationInput");

  {
      elapse_read = benchmark([&]() {
          adios2::Engine reader = io_in.Open(read_name, adios2::Mode::Read);

          auto attr_n = io_in.InquireAttribute<type::idx>("num");
          if(attr_n) {
              num_read = attr_n.Data()[0];
          } else {
             // Fallback or error
          }

          // Allocate read buffers if not already (first time)
          // Since benchmark calls func, we need to be careful about allocation inside benchmark?
          // Benchmark wrapper just times the call.
          // Allocation should probably be outside if we want to measure IO only.
          // But num_read is only known after Open/Inquire.
          // For fair comparison with original code: original code included H5Dread_multi which reads into buffer.
          // Original code allocated *before* benchmark execution.
          // But original code knew `num_read` before benchmark by `read_attr`.
      });
  }

  // To match original structure, we should read "num" first, allocate, then benchmark the data read.
  {
     adios2::IO io_pre = ad.DeclareIO("PreRead");
     adios2::Engine r = io_pre.Open(read_name, adios2::Mode::Read);
     auto attr_n = io_pre.InquireAttribute<type::idx>("num");
     if(attr_n) num_read = attr_n.Data()[0];
     r.Close();
     ad.RemoveIO("PreRead");
  }

  if (num_read != num) {
    std::cerr << "rank " << mpi_rank << ": ERROR: num_read (" << num_read << ") does not match with num (" << num << ")" << std::endl;
    MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    std::exit(EXIT_FAILURE);
  }

  allocate_particles(&pos_read, &vel_xy_read, &vel_z_read, &idx_read, num_read);

  MPI_Barrier(MPI_COMM_WORLD);
  {
      elapse_read = benchmark([&]() {
          adios2::Engine reader = io_in.Open(read_name, adios2::Mode::Read);

          auto r_id = io_in.InquireVariable<type::idx>("id");
          auto r_pos = io_in.InquireVariable<float>("pos_mass");
          auto r_vxy = io_in.InquireVariable<float>("vel_xy");
          auto r_vz = io_in.InquireVariable<float>("vel_z");

          if(r_id && r_pos && r_vxy && r_vz) {
              r_id.SetSelection({{0}, {num_read}});
              r_pos.SetSelection({{0, 0}, {num_read, 4}});
              r_vxy.SetSelection({{0, 0}, {num_read, 2}});
              r_vz.SetSelection({{0}, {num_read}});

              reader.Get(r_id, idx_read);
              reader.Get(r_pos, reinterpret_cast<float*>(pos_read));
              reader.Get(r_vxy, reinterpret_cast<float*>(vel_xy_read));
              reader.Get(r_vz, vel_z_read);
              reader.PerformGets();
          }
          reader.Close();
      });
  }

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
    output << "," << 0; // cbuf removed
    output << "," << 0; // fblk removed
    output << "," << 0; // memb removed
    output << "," << elapse_write;
    output << "," << elapse_read;
    output << "," << datasize / elapse_write;
    output << "," << datasize / elapse_read;
    output << "," << name;
    output << std::endl;
    output.close();

    // Aggregated results
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
    std::cerr << "rank " << mpi_rank << ": ERROR: read data does not match with the original data" << std::endl
              << std::flush;
    MPI_Abort(MPI_COMM_WORLD, EXIT_FAILURE);
    std::exit(EXIT_FAILURE);
  }

  release_particles(pos, vel_xy, vel_z, idx);
  release_particles(pos_read, vel_xy_read, vel_z_read, idx_read);

  MPI_Finalize();
  std::exit(EXIT_SUCCESS);
}
