#include <cufile.h>

#include <thrust/device_ptr.h>
#include <thrust/equal.h>
#include <thrust/execution_policy.h>

#include <boost/filesystem.hpp>            // boost::filesystem
#include <boost/lexical_cast.hpp>          // boost::lexical_cast
#include <boost/program_options.hpp>       // boost::program_options
#include <boost/uuid/uuid_generators.hpp>  // boost::uuids::random_generator
#include <boost/uuid/uuid_io.hpp>          // convert boost::uuids::uuid to std::string
#include <cstdlib>                         // std::exit
#include <cstring>                         // std::memcpy
#include <fstream>                         // std::ofstream
#include <iomanip>                         // std::setw
#include <iostream>                        // std::cout
#include <sstream>                         // std::stringstream
#include <string>                          // std::string

#include <fcntl.h>   // open(), O_DIRECT
#include <unistd.h>  // close(), write(), read()

#include "allocate.cuh"
#include "common.cuh"
#include "generate.cuh"

static constexpr type::vel_z newton = 1.0F;  // gravitational constant in the computational unit

// Alignment for Direct I/O (typically 512 or 4096 bytes)
static constexpr size_t ALIGNMENT = 4096;

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

// Helper function to align size to alignment boundary
static inline size_t align_size(size_t size, size_t alignment) {
  return ((size + alignment - 1) / alignment) * alignment;
}

// cuFile error checking macro
#define CHECK_CUFILE_ERROR(call)                                                     \
  do {                                                                               \
    CUfileError_t status = (call);                                                   \
    if (status.err != CU_FILE_SUCCESS) {                                             \
      std::cerr << "cuFile error at " << __FILE__ << ":" << __LINE__ << " - "        \
                << "Error code: " << status.err << std::endl;                        \
      std::exit(EXIT_FAILURE);                                                       \
    }                                                                                \
  } while (0)

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
      "skip", boost::program_options::bool_switch()->default_value(false), "skip consistency check between read and original data")(
      "cufile", boost::program_options::bool_switch()->default_value(false), "use cuFile API (GPUDirect Storage)")(
      "direct", boost::program_options::bool_switch()->default_value(false), "use POSIX Direct I/O (O_DIRECT)")(
      "posix", boost::program_options::bool_switch()->default_value(false), "use standard POSIX I/O (page cache)")(
      "virial", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(0.2), "Virial ratio of the system")(
      "radius", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "radius of the system")(
      "mass", boost::program_options::value<std::remove_const_t<decltype(newton)>>()->default_value(1.0), "total mass of the system")(
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
  const auto virial = vm["virial"].as<decltype(newton)>();
  const auto radius = vm["radius"].as<decltype(newton)>();
  const auto mass = vm["mass"].as<decltype(newton)>();
  const auto skip = vm["skip"].as<bool>();
  const auto use_cufile = vm["cufile"].as<bool>();
  const auto use_direct = vm["direct"].as<bool>();
  const auto use_posix = vm["posix"].as<bool>();
  vm.clear();

  // Check that at least one I/O method is selected
  if (!use_cufile && !use_direct && !use_posix) {
    std::cerr << "Error: At least one I/O method must be selected (--cufile, --direct, or --posix)" << std::endl;
    std::exit(EXIT_FAILURE);
  }

  // Initialize cuFile driver if needed
  if (use_cufile) {
    CHECK_CUFILE_ERROR(cuFileDriverOpen());
  }

  // memory allocation
  cudaSetDevice(0);
  
  // Print memory allocation strategy
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
  std::cout << "Memory allocation strategy: DEVICE MEMORY (cudaMalloc)" << std::endl;
  type::idx *idx = nullptr;        // particle ID
  type::pos *pos = nullptr;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy = nullptr;  // velocity (x, y)
  type::vel_z *vel_z = nullptr;    // velocity (z)
#else
  std::cout << "Memory allocation strategy: UNIFIED MEMORY (HOST_MALLOC_AND_FIRST_TOUCH)" << std::endl;
  type::idx *idx;        // particle ID
  type::pos *pos;        // position (x, y, z) and mass (w)
  type::vel_xy *vel_xy;  // velocity (x, y)
  type::vel_z *vel_z;  // velocity (z)
#endif
  allocate_particles(&pos, &vel_xy, &vel_z, &idx, num);

  // initialize data on GPU
  set_uniform_sphere(num, pos, vel_xy, vel_z, idx, mass, radius, virial, newton);

  constexpr auto benchmark = [](const auto func) noexcept(false) {
    struct timespec ini;
    clock_gettime(CLOCK_MONOTONIC, &ini);
    func();
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &end);
    return (std::fma(1.0e-9, static_cast<double>(end.tv_nsec - ini.tv_nsec), end.tv_sec - ini.tv_sec));
  };

  // Calculate data sizes
  const auto datasize = static_cast<double>(num) * static_cast<double>(sizeof(std::remove_reference_t<decltype(*idx)>) + sizeof(std::remove_reference_t<decltype(*pos)>) + sizeof(std::remove_reference_t<decltype(*vel_xy)>) + sizeof(std::remove_reference_t<decltype(*vel_z)>));
  const size_t idx_size = num * sizeof(std::remove_reference_t<decltype(*idx)>);
  const size_t pos_size = num * sizeof(std::remove_reference_t<decltype(*pos)>);
  const size_t vel_xy_size = num * sizeof(std::remove_reference_t<decltype(*vel_xy)>);
  const size_t vel_z_size = num * sizeof(std::remove_reference_t<decltype(*vel_z)>);
  const size_t total_size = idx_size + pos_size + vel_xy_size + vel_z_size;

  // Array to store I/O methods to test
  std::vector<std::string> io_methods;
  if (use_cufile) io_methods.push_back("cufile");
  if (use_direct) io_methods.push_back("direct");
  if (use_posix) io_methods.push_back("posix");

  // Prepare CSV output file
  const std::string report = "log/bingds_benchmark.csv";
  const boost::filesystem::path previous(report);
  boost::system::error_code err;
  const auto exist = boost::filesystem::exists(previous, err);

  std::ofstream output(report, std::ios::app);
  if (!exist || err) {
    output << "N";
    output << ",data size [byte]";
    output << ",I/O method";
    output << ",latency (write) [s]";
    output << ",latency (read) [s]";
    output << ",bandwidth (write) [byte/s]";
    output << ",bandwidth (read) [byte/s]";
    output << ",filename";
    output << std::endl;
  }

  // Test each I/O method
  for (const auto& method : io_methods) {
    auto uuid = boost::uuids::random_generator{}();
    const auto series = boost::lexical_cast<std::string>(uuid);
    auto name = "dat/" + series + "_" + method + ".bin";
    
    double elapse_write = 0.0;
    double elapse_read = 0.0;
    bool success = false;

    std::cout << "Testing I/O method: " << method << std::endl;

    // Allocate memory for read verification
    std::remove_reference_t<decltype(*idx)> *idx_read = nullptr;
    std::remove_reference_t<decltype(*pos)> *pos_read = nullptr;
    std::remove_reference_t<decltype(*vel_xy)> *vel_xy_read = nullptr;
    std::remove_reference_t<decltype(*vel_z)> *vel_z_read = nullptr;
    allocate_particles(&pos_read, &vel_xy_read, &vel_z_read, &idx_read, num);

    if (method == "cufile") {
      int fd_write = open(name.c_str(), O_CREAT | O_WRONLY | O_DIRECT, 0644);
      if (fd_write < 0) {
        std::cerr << "Failed to open file for cuFile write: " << name << std::endl;
        std::exit(EXIT_FAILURE);
      }
      
      CUfileDescr_t cf_descr_write;
      memset(&cf_descr_write, 0, sizeof(CUfileDescr_t));
      cf_descr_write.handle.fd = fd_write;
      cf_descr_write.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
      CUfileHandle_t cf_handle_write;
      CHECK_CUFILE_ERROR(cuFileHandleRegister(&cf_handle_write, &cf_descr_write));

      // Benchmark only the actual write operations
      elapse_write = benchmark([&]() {
        size_t offset = 0;
        cuFileWrite(cf_handle_write, (void*)idx, idx_size, offset, 0); offset += idx_size;
        cuFileWrite(cf_handle_write, (void*)pos, pos_size, offset, 0); offset += pos_size;
        cuFileWrite(cf_handle_write, (void*)vel_xy, vel_xy_size, offset, 0); offset += vel_xy_size;
        cuFileWrite(cf_handle_write, (void*)vel_z, vel_z_size, offset, 0);
      });

      // Deregister and close (NOT timed)
      cuFileHandleDeregister(cf_handle_write);  // Returns void, no error checking needed
      close(fd_write);

      // ===== cuFile Read =====
      // Open file and register handle (NOT timed)
      int fd_read = open(name.c_str(), O_RDONLY | O_DIRECT);
      if (fd_read < 0) {
        std::cerr << "Failed to open file for cuFile read: " << name << std::endl;
        std::exit(EXIT_FAILURE);
      }
      
      CUfileDescr_t cf_descr_read;
      memset(&cf_descr_read, 0, sizeof(CUfileDescr_t));
      cf_descr_read.handle.fd = fd_read;
      cf_descr_read.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
      CUfileHandle_t cf_handle_read;
      CHECK_CUFILE_ERROR(cuFileHandleRegister(&cf_handle_read, &cf_descr_read));

      // Benchmark only the actual read operations
      elapse_read = benchmark([&]() {
        size_t offset = 0;
        cuFileRead(cf_handle_read, (void*)idx_read, idx_size, offset, 0); offset += idx_size;
        cuFileRead(cf_handle_read, (void*)pos_read, pos_size, offset, 0); offset += pos_size;
        cuFileRead(cf_handle_read, (void*)vel_xy_read, vel_xy_size, offset, 0); offset += vel_xy_size;
        cuFileRead(cf_handle_read, (void*)vel_z_read, vel_z_size, offset, 0);
      });

      // Deregister and close (NOT timed)
      cuFileHandleDeregister(cf_handle_read);  // Returns void, no error checking needed
      close(fd_read);
    } else if (method == "direct") {
      // ===== Direct I/O Write =====
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      // For device memory, need aligned buffer
      size_t aligned_size = align_size(total_size, ALIGNMENT);
      void* aligned_buffer_write = nullptr;
      if (posix_memalign(&aligned_buffer_write, ALIGNMENT, aligned_size) != 0) {
        std::cerr << "Failed to allocate aligned buffer" << std::endl;
        std::exit(EXIT_FAILURE);
      }
#endif

      // Open file (NOT timed)
      int fd_write = open(name.c_str(), O_CREAT | O_WRONLY | O_DIRECT, 0644);
      if (fd_write < 0) {
        std::cerr << "Failed to open file for Direct I/O write" << std::endl;
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        free(aligned_buffer_write);
#endif
        std::exit(EXIT_FAILURE);
      }

      // Benchmark: data copy + write (this is the I/O pipeline)
      elapse_write = benchmark([&]() {
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        char* buf_ptr = (char*)aligned_buffer_write;
        cudaMemcpy(buf_ptr, idx, idx_size, cudaMemcpyDeviceToHost); buf_ptr += idx_size;
        cudaMemcpy(buf_ptr, pos, pos_size, cudaMemcpyDeviceToHost); buf_ptr += pos_size;
        cudaMemcpy(buf_ptr, vel_xy, vel_xy_size, cudaMemcpyDeviceToHost); buf_ptr += vel_xy_size;
        cudaMemcpy(buf_ptr, vel_z, vel_z_size, cudaMemcpyDeviceToHost);
        write(fd_write, aligned_buffer_write, aligned_size);
#else
        write(fd_write, idx, idx_size);
        write(fd_write, pos, pos_size);
        write(fd_write, vel_xy, vel_xy_size);
        write(fd_write, vel_z, vel_z_size);
#endif
      });

      // Close and cleanup (NOT timed)
      close(fd_write);
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      free(aligned_buffer_write);
#endif


      // ===== Direct I/O Read =====
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      // For device memory, need aligned buffer
      void* aligned_buffer_read = nullptr;
      if (posix_memalign(&aligned_buffer_read, ALIGNMENT, aligned_size) != 0) {
        std::cerr << "Failed to allocate aligned buffer" << std::endl;
        std::exit(EXIT_FAILURE);
      }
#endif

      // Open file (NOT timed)
      int fd_read = open(name.c_str(), O_RDONLY | O_DIRECT);
      if (fd_read < 0) {
        std::cerr << "Failed to open file for Direct I/O read" << std::endl;
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        free(aligned_buffer_read);
#endif
        std::exit(EXIT_FAILURE);
      }

      // Benchmark: read + data copy (this is the I/O pipeline)
      elapse_read = benchmark([&]() {
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        read(fd_read, aligned_buffer_read, aligned_size);
        
        char* buf_ptr = (char*)aligned_buffer_read;
        cudaMemcpy(idx_read, buf_ptr, idx_size, cudaMemcpyHostToDevice); buf_ptr += idx_size;
        cudaMemcpy(pos_read, buf_ptr, pos_size, cudaMemcpyHostToDevice); buf_ptr += pos_size;
        cudaMemcpy(vel_xy_read, buf_ptr, vel_xy_size, cudaMemcpyHostToDevice); buf_ptr += vel_xy_size;
        cudaMemcpy(vel_z_read, buf_ptr, vel_z_size, cudaMemcpyHostToDevice);
#else
        // For unified memory, read directly (memory is already aligned for GH200)
        read(fd_read, idx_read, idx_size);
        read(fd_read, pos_read, pos_size);
        read(fd_read, vel_xy_read, vel_xy_size);
        read(fd_read, vel_z_read, vel_z_size);
#endif
      });

      // Close file (NOT timed)
      close(fd_read);
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      free(aligned_buffer_read);
#endif
    } else if (method == "posix") {
      // ===== Standard POSIX Write =====
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      // For device memory, need intermediate buffer
      void* host_buffer_write = malloc(total_size);
      if (!host_buffer_write) {
        std::cerr << "Failed to allocate host buffer" << std::endl;
        std::exit(EXIT_FAILURE);
      }
#endif

      // Open file (NOT timed)
      int fd_write = open(name.c_str(), O_CREAT | O_WRONLY, 0644);
      if (fd_write < 0) {
        std::cerr << "Failed to open file for POSIX write" << std::endl;
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        free(host_buffer_write);
#endif
        std::exit(EXIT_FAILURE);
      }

      // Benchmark: data copy + write (this is the I/O pipeline)
      elapse_write = benchmark([&]() {
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        char* buf_ptr = (char*)host_buffer_write;
        cudaMemcpy(buf_ptr, idx, idx_size, cudaMemcpyDeviceToHost); buf_ptr += idx_size;
        cudaMemcpy(buf_ptr, pos, pos_size, cudaMemcpyDeviceToHost); buf_ptr += pos_size;
        cudaMemcpy(buf_ptr, vel_xy, vel_xy_size, cudaMemcpyDeviceToHost); buf_ptr += vel_xy_size;
        cudaMemcpy(buf_ptr, vel_z, vel_z_size, cudaMemcpyDeviceToHost);
        write(fd_write, host_buffer_write, total_size);
#else
        // For unified memory, write directly from unified memory pointers
        write(fd_write, idx, idx_size);
        write(fd_write, pos, pos_size);
        write(fd_write, vel_xy, vel_xy_size);
        write(fd_write, vel_z, vel_z_size);
#endif
      });

      close(fd_write);
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      free(host_buffer_write);
#endif


      // ===== Standard POSIX Read =====
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      // For device memory, need intermediate buffer
      void* host_buffer_read = malloc(total_size);
      if (!host_buffer_read) {
        std::cerr << "Failed to allocate host buffer" << std::endl;
        std::exit(EXIT_FAILURE);
      }
#endif

      // Open file (NOT timed)
      int fd_read = open(name.c_str(), O_RDONLY);
      if (fd_read < 0) {
        std::cerr << "Failed to open file for POSIX read" << std::endl;
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        free(host_buffer_read);
#endif
        std::exit(EXIT_FAILURE);
      }

      elapse_read = benchmark([&]() {
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
        read(fd_read, host_buffer_read, total_size);
        char* buf_ptr = (char*)host_buffer_read;
        cudaMemcpy(idx_read, buf_ptr, idx_size, cudaMemcpyHostToDevice); buf_ptr += idx_size;
        cudaMemcpy(pos_read, buf_ptr, pos_size, cudaMemcpyHostToDevice); buf_ptr += pos_size;
        cudaMemcpy(vel_xy_read, buf_ptr, vel_xy_size, cudaMemcpyHostToDevice); buf_ptr += vel_xy_size;
        cudaMemcpy(vel_z_read, buf_ptr, vel_z_size, cudaMemcpyHostToDevice);
#else
        // For unified memory, read directly into unified memory pointers
        read(fd_read, idx_read, idx_size);
        read(fd_read, pos_read, pos_size);
        read(fd_read, vel_xy_read, vel_xy_size);
        read(fd_read, vel_z_read, vel_z_size);
#endif
      });

      // Close file (NOT timed)
      close(fd_read);
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
      free(host_buffer_read);
#endif
    }

    // Ensure all memory transfers are complete before verification
    cudaDeviceSynchronize();

    // Verify read data
    success = skip ? true : (thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)idx, (thrust::device_ptr<std::remove_reference_t<decltype(*idx)>>)(idx + num), (thrust::device_ptr<std::remove_reference_t<decltype(*idx_read)>>)idx_read) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)pos, (thrust::device_ptr<std::remove_reference_t<decltype(*pos)>>)(pos + num), (thrust::device_ptr<std::remove_reference_t<decltype(*pos_read)>>)pos_read, compare_pos()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)vel_xy, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy)>>)(vel_xy + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_xy_read)>>)vel_xy_read, compare_vel_xy()) && thrust::equal(thrust::device, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)vel_z, (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z)>>)(vel_z + num), (thrust::device_ptr<std::remove_reference_t<decltype(*vel_z_read)>>)vel_z_read));

    if (success) {
      std::cout << "  Write: " << elapse_write << " s, " << (datasize / elapse_write) << " byte/s" << std::endl;
      std::cout << "  Read:  " << elapse_read << " s, " << (datasize / elapse_read) << " byte/s" << std::endl;

      // Write to CSV
      output << std::scientific;
      output << num;
      output << "," << datasize;
      output << "," << method;
      output << "," << elapse_write;
      output << "," << elapse_read;
      output << "," << datasize / elapse_write;
      output << "," << datasize / elapse_read;
      output << "," << name;
      output << std::endl;
    } else {
      std::cerr << "Data verification failed for method: " << method << std::endl;
    }

    // Clean up read buffers
    release_particles(pos_read, vel_xy_read, vel_z_read, idx_read);
  }

  output.close();

  // Clean up
  release_particles(pos, vel_xy, vel_z, idx);

  // Close cuFile driver if it was opened
  if (use_cufile) {
    CHECK_CUFILE_ERROR(cuFileDriverClose());
  }

  std::exit(EXIT_SUCCESS);
}
