///
/// @file src/hdf5.hpp
/// @author Yohei MIKI (The University of Tokyo)
/// @brief utility functions using HDF5
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#ifndef HDF5_HPP
#define HDF5_HPP

#include <hdf5.h>  // HDF5

#include <cassert>      // assert
#include <complex>      // std::complex (to commit a new datatype)
#include <cstdint>      // int??_t
#include <cstdlib>      // std::exit
#include <iostream>     // std::cerr
#include <string>       // std::string
#include <tuple>        // std::make_tuple
#include <type_traits>  // std::remove_reference_t
#include <vector>       // std::vector

// ///
// /// @brief enable Gzip compression
// ///
// #define USE_GZIP_COMPRESSION

///
/// @brief utility functions for HDF5
///
namespace util::hdf5 {
///
/// @brief error handler of HDF5 function
///
/// @param[in] err error ID of HDF5 function
/// @param[in] file file name who calls the HDF5 function
/// @param[in] line number of line which calls the HDF5 function
/// @param[in] func name of function which calls the HDF5 function
///
constexpr auto _call_hdf5(const herr_t err, const char *file, const int32_t line, const char *func) noexcept(false) {
  if (err < 0) {
    std::cerr << file << "(" << line << "): " << func << ": ERROR: HDF5 returns error ID " << err << std::endl
              << std::flush;
#ifdef USE_MPI
    MPI_Abort(MPI_COMM_WORLD, 1);
#endif  // USE_MPI
    std::exit(EXIT_FAILURE);
  }
}

///
/// @brief parser to call error handler of HDF5 function
///
constexpr auto call(const herr_t err) noexcept(false) { _call_hdf5(err, __FILE__, __LINE__, __func__); }

#ifdef USE_GZIP_COMPRESSION
///
/// @brief The maximum number of elements in a chunk in HDF5 is 2^32-1 which is equal to 4,294,967,295
///
constexpr auto MAXIMUM_CHUNK_SIZE() { return (hsize_t{1} << 31U); }

///
/// @brief The maximum size for any chunk in HDF5 is 4 GB; it is 2^27 for 32bits variables
///
constexpr auto MAXIMUM_CHUNK_SIZE_32BIT() { return (hsize_t{1} << 27U); }

///
/// @brief The maximum size for any chunk in HDF5 is 4 GB; it is 2^26 for 64bits variables
///
constexpr auto MAXIMUM_CHUNK_SIZE_64BIT() { return (hsize_t{1} << 26U); }
#endif  // USE_GZIP_COMPRESSION

// user-defined datatype for 2-dimensional vector
#include <vector_types.h>                   // definition of [float double][2 4] in CUDA C++
static bool h5t_real2_initialized = false;  // flag to check whether are h5t_*2 initialized or not
static hid_t h5t_flt2 = H5I_INVALID_HID;    // user-defined datatype for float2 in HDF5
static hid_t h5t_dbl2 = H5I_INVALID_HID;    // user-defined datatype for double2 in HDF5

///
/// @brief create user-defined datatype for 2-dimensional vector
///
[[maybe_unused]] static void create_h5t_real2() noexcept(true) {
  if (!h5t_real2_initialized) {
    h5t_flt2 = H5Tcreate(H5T_COMPOUND, sizeof(float2));
    call(H5Tinsert(h5t_flt2, "x", HOFFSET(float2, x), H5T_NATIVE_FLOAT));
    call(H5Tinsert(h5t_flt2, "y", HOFFSET(float2, y), H5T_NATIVE_FLOAT));
    h5t_dbl2 = H5Tcreate(H5T_COMPOUND, sizeof(double2));
    call(H5Tinsert(h5t_dbl2, "x", HOFFSET(double2, x), H5T_NATIVE_DOUBLE));
    call(H5Tinsert(h5t_dbl2, "y", HOFFSET(double2, y), H5T_NATIVE_DOUBLE));
    h5t_real2_initialized = true;
  }
  assert(h5t_real2_initialized);
}

///
/// @brief remove user-defined datatype for 2-dimensional vector
///
[[maybe_unused]] static void remove_h5t_real2() noexcept(true) {
  if (h5t_real2_initialized) {
    call(H5Tclose(h5t_flt2));
    call(H5Tclose(h5t_dbl2));
    h5t_real2_initialized = false;
  }
  assert(!h5t_real2_initialized);
}

// user-defined datatype for 4-dimensional vector
static bool h5t_real4_initialized = false;  // flag to check whether are h5t_*4 initialized or not
static hid_t h5t_flt4 = H5I_INVALID_HID;    // user-defined datatype for float4 in HDF5
static hid_t h5t_dbl4 = H5I_INVALID_HID;    // user-defined datatype for double4 in HDF5

///
/// @brief create user-defined datatype for 4-dimensional vector
///
[[maybe_unused]] static void create_h5t_real4() noexcept(true) {
  if (!h5t_real4_initialized) {
    h5t_flt4 = H5Tcreate(H5T_COMPOUND, sizeof(float4));
    call(H5Tinsert(h5t_flt4, "x", HOFFSET(float4, x), H5T_NATIVE_FLOAT));
    call(H5Tinsert(h5t_flt4, "y", HOFFSET(float4, y), H5T_NATIVE_FLOAT));
    call(H5Tinsert(h5t_flt4, "z", HOFFSET(float4, z), H5T_NATIVE_FLOAT));
    call(H5Tinsert(h5t_flt4, "w", HOFFSET(float4, w), H5T_NATIVE_FLOAT));
    h5t_dbl4 = H5Tcreate(H5T_COMPOUND, sizeof(double4));
    call(H5Tinsert(h5t_dbl4, "x", HOFFSET(double4, x), H5T_NATIVE_DOUBLE));
    call(H5Tinsert(h5t_dbl4, "y", HOFFSET(double4, y), H5T_NATIVE_DOUBLE));
    call(H5Tinsert(h5t_dbl4, "z", HOFFSET(double4, z), H5T_NATIVE_DOUBLE));
    call(H5Tinsert(h5t_dbl4, "w", HOFFSET(double4, w), H5T_NATIVE_DOUBLE));
    h5t_real4_initialized = true;
  }
  assert(h5t_real4_initialized);
}

///
/// @brief remove user-defined datatype for 4-dimensional vector
///
[[maybe_unused]] static void remove_h5t_real4() noexcept(true) {
  if (h5t_real4_initialized) {
    call(H5Tclose(h5t_flt4));
    call(H5Tclose(h5t_dbl4));
    h5t_real4_initialized = false;
  }
  assert(!h5t_real4_initialized);
}

// semi-automatic selection of appropriate H5T_* for input datatype
[[maybe_unused]] static auto h5type([[maybe_unused]] const int16_t val) noexcept(true) { return (H5T_NATIVE_SHORT); }        // returns predefined native datatype for int16_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const int32_t val) noexcept(true) { return (H5T_NATIVE_INT); }          // returns predefined native datatype for int32_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const int64_t val) noexcept(true) { return (H5T_NATIVE_LONG); }         // returns predefined native datatype for int64_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const uint16_t val) noexcept(true) { return (H5T_NATIVE_USHORT); }      // returns predefined native datatype for uint16_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const uint32_t val) noexcept(true) { return (H5T_NATIVE_UINT); }        // returns predefined native datatype for uint32_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const uint64_t val) noexcept(true) { return (H5T_NATIVE_ULONG); }       // returns predefined native datatype for uint64_t
[[maybe_unused]] static auto h5type([[maybe_unused]] const float val) noexcept(true) { return (H5T_NATIVE_FLOAT); }          // returns predefined native datatype for float
[[maybe_unused]] static auto h5type([[maybe_unused]] const double val) noexcept(true) { return (H5T_NATIVE_DOUBLE); }        // returns predefined native datatype for double
[[maybe_unused]] static auto h5type([[maybe_unused]] const long double val) noexcept(true) { return (H5T_NATIVE_LDOUBLE); }  // returns predefined native datatype for long double
[[maybe_unused]] static auto h5type([[maybe_unused]] const float2 &val) noexcept(true) { return (h5t_flt2); }                // returns user-define datatype for util::type::float2
[[maybe_unused]] static auto h5type([[maybe_unused]] const double2 &val) noexcept(true) { return (h5t_dbl2); }               // returns user-define datatype for util::type::double2
[[maybe_unused]] static auto h5type([[maybe_unused]] const float4 &val) noexcept(true) { return (h5t_flt4); }                // returns user-define datatype for util::type::float4
[[maybe_unused]] static auto h5type([[maybe_unused]] const double4 &val) noexcept(true) { return (h5t_dbl4); }               // returns user-define datatype for util::type::double4

///
/// @brief base class to ease usage of H5D[read write]_multi()
///
class h5multi {
 public:
  ///
  /// @brief allocate arrays to use H5D[read write]_multi()
  ///
  /// @param[in] num number of elements
  ///
  void allocate(const size_t num) noexcept(false) {
    if (max_count <= num) {
      dataset = new std::remove_reference_t<decltype(*dataset)>[num];
      memory_type = new std::remove_reference_t<decltype(*memory_type)>[num];
      memory_space = new std::remove_reference_t<decltype(*memory_space)>[num];
      file_space = new std::remove_reference_t<decltype(*file_space)>[num];
      buffer = new std::remove_reference_t<decltype(*buffer)>[num];
      max_count = num;
    } else {
      release();
      allocate(num);
    }
    assert(max_count != 0UL);
  }

  ///
  /// @brief Construct a new h5multi object
  ///
  h5multi() = default;

  ///
  /// @brief Destroy the h5multi object
  ///
  ~h5multi() noexcept(false) {
    release();
  }

  ///
  /// @brief delete defaulted copy constructor
  ///
  h5multi(const h5multi &) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(const h5multi &) noexcept(true) -> h5multi & = delete;

  ///
  /// @brief delete defaulted move constructor
  ///
  h5multi(h5multi &&) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(h5multi &&) noexcept(true) -> h5multi & = delete;

  ///
  /// @brief Get the last dataset object
  ///
  /// @return constexpr auto
  ///
  constexpr auto get_last_dataset() const noexcept(false) {
    return (dataset[count - 1UL]);
  }

 protected:
  ///
  /// @brief close opened datasets
  ///
  void flush() noexcept(false) {
    if (count != 0UL) {
      for (auto ii = static_cast<decltype(count)>(0); ii < count; ii++) {
        const auto target = dataset[ii];
        if (H5Iis_valid(target) > 0) {
          call(H5Dclose(target));
        }
      }
      count = 0UL;
    }
    assert(count == 0UL);
  }

  ///
  /// @brief deallocate arrays
  ///
  void release() noexcept(false) {
    flush();
    if (max_count != 0UL) {
      delete[] dataset;
      delete[] memory_type;
      delete[] memory_space;
      delete[] file_space;
      delete[] buffer;
      max_count = 0UL;
    }
    assert(max_count == 0UL);
  }

  hid_t *dataset = nullptr;       // identifier of the datasets to read/write
  hid_t *memory_type = nullptr;   // identifier of the memory datatypes
  hid_t *memory_space = nullptr;  // identifier of the memory dataspace
  hid_t *file_space = nullptr;    // identifier of the datasets' dataspace in the file
  void **buffer = nullptr;        // buffers to read/write the data
  size_t count = 0UL;             // number of commited elements
  size_t max_count = 0UL;         // maximum number of committable elements
};

///
/// @brief class to ease usage of H5Dwrite_multi()
///
class h5multi_write : public h5multi {
 public:
  ///
  /// @brief commit an element as target of H5Dwrite_multi()
  ///
  /// @tparam Type
  /// @param[in] _buffer buffer with data to be written to the file
  /// @param[in] _dataset identifier of the dataset
  /// @param[in] _datatype identifier of the datatype
  /// @param[in] _memory_space identifier of the memory dataspace (optional)
  /// @param[in] _file_space identifier of the dataset's dataspace in the file (optional)
  ///
  template <class Type>
  void commit(Type *_buffer, const hid_t _dataset, const hid_t _datatype, const hid_t _memory_space = H5S_ALL, const hid_t _file_space = H5S_ALL) noexcept(false) {
    assert(count < max_count);
    memory_space[count] = _memory_space;
    file_space[count] = _file_space;
    memory_type[count] = _datatype;
    dataset[count] = _dataset;
    buffer[count] = _buffer;
    count++;
  }

  ///
  /// @brief commit an element as target of H5Dwrite_multi()
  ///
  /// @tparam Type
  /// @param[in] dataspace identifier of the dataspace
  /// @param[in] vessel object identifier (group in most cases)
  /// @param[in] name name of the dataset
  /// @param[in] _datatype identifier of the datatype
  /// @param[in] _buffer buffer with data to be written to the file
  /// @param[in] _memory_space identifier of the memory dataspace (optional)
  /// @param[in] _file_space identifier of the dataset's dataspace in the file (optional)
  ///
  template <class Type>
  void commit(const hid_t dataspace, const hid_t vessel, const char *name, const hid_t _datatype, Type *_buffer, const hid_t _memory_space = H5S_ALL, const hid_t _file_space = H5S_ALL) noexcept(false) {
    assert(count < max_count);
    constexpr auto link_creation = H5P_DEFAULT;
    constexpr auto creation_property = H5P_DEFAULT;
    constexpr auto access_property = H5P_DEFAULT;
    commit(_buffer, H5Dcreate(vessel, name, _datatype, dataspace, link_creation, creation_property, access_property), _datatype, _memory_space, _file_space);
  }

  ///
  /// @brief execute H5Dwrite_multi()
  ///
  /// @param[in] transfer_property identifier of the transfer property list for this I/O operation (optional)
  ///
  void execute(const hid_t transfer_property = H5P_DEFAULT) noexcept(false) {
    call(H5Dwrite_multi(count, dataset, memory_type, memory_space, file_space, transfer_property, (const void **)buffer));
    flush();
  }

  ///
  /// @brief Construct a new h5multi_write object
  ///
  h5multi_write() = default;

  ///
  /// @brief Destroy the h5multi_write object
  ///
  ~h5multi_write() noexcept(false) {
    release();
  }

  ///
  /// @brief delete defaulted copy constructor
  ///
  h5multi_write(const h5multi_write &) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(const h5multi_write &) noexcept(true) -> h5multi_write & = delete;

  ///
  /// @brief delete defaulted move constructor
  ///
  h5multi_write(h5multi_write &&) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(h5multi_write &&) noexcept(true) -> h5multi_write & = delete;
};

///
/// @brief class to ease usage of H5Dread_multi()
///
class h5multi_read : public h5multi {
 public:
  template <class Type>
  ///
  /// @brief commit an element as target of H5Dread_multi()
  ///
  /// @tparam Type
  /// @param[in] _buffer buffer with data to be read from the file
  /// @param[in] _dataset identifier of the dataset
  /// @param[in] _datatype identifier of the datatype
  /// @param[in] _memory_space identifier of the memory dataspace (optional)
  /// @param[in] _file_space identifier of the dataset's dataspace in the file (optional)
  ///
  void commit(Type *_buffer, const hid_t _dataset, const hid_t _datatype, const hid_t _memory_space = H5S_ALL, const hid_t _file_space = H5S_ALL) noexcept(false) {
    assert(count < max_count);
    memory_space[count] = _memory_space;
    file_space[count] = _file_space;
    memory_type[count] = _datatype;
    dataset[count] = _dataset;
    buffer[count] = _buffer;
    count++;
  }

  ///
  /// @brief commit an element as target of H5Dread_multi()
  ///
  /// @tparam Type
  /// @param[in] vessel object identifier (group in most cases)
  /// @param[in] name name of the dataset
  /// @param[in] _datatype identifier of the datatype
  /// @param[in] _buffer buffer to receive data read from file
  /// @param[in] _memory_space identifier of the memory dataspace (optional)
  /// @param[in] _file_space identifier of the dataset's dataspace in the file (optional)
  ///
  template <class Type>
  void commit(const hid_t vessel, const char *name, const hid_t _datatype, Type *_buffer, const hid_t _memory_space = H5S_ALL, const hid_t _file_space = H5S_ALL) noexcept(false) {
    constexpr auto link_access_property = H5P_DEFAULT;
    if (H5Lexists(vessel, name, link_access_property)) {
      constexpr auto access_property = H5P_DEFAULT;
      commit(_buffer, H5Dopen(vessel, name, access_property), _datatype, _memory_space, _file_space);
    }
  }

  ///
  /// @brief execute H5Dread_multi()
  ///
  /// @param transfer_property identifier of the transfer property list for this I/O operation (optional)
  ///
  void execute(const hid_t transfer_property = H5P_DEFAULT) noexcept(false) {
    call(H5Dread_multi(count, dataset, memory_type, memory_space, file_space, transfer_property, buffer));
    flush();
  }

  ///
  /// @brief Construct a new h5multi_read object
  ///
  h5multi_read() = default;

  ///
  /// @brief Destroy the h5multi_read object
  ///
  ~h5multi_read() noexcept(false) {
    release();
  }

  ///
  /// @brief delete defaulted copy constructor
  ///
  h5multi_read(const h5multi_read &) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(const h5multi_read &) noexcept(true) -> h5multi_read & = delete;

  ///
  /// @brief delete defaulted move constructor
  ///
  h5multi_read(h5multi_read &&) noexcept(true) = delete;
  ///
  /// @brief delete defaulted move assignment operator
  ///
  auto operator=(h5multi_read &&) noexcept(true) -> h5multi_read & = delete;
};

///
/// @brief create a new simple dataspace
///
/// @param[in] dims size of the dataspace
/// @return identifier of the new dataspace
///
[[maybe_unused]] static inline auto setup_dataspace(const hsize_t dims = static_cast<hsize_t>(1)) noexcept(false) -> hid_t {
  return (H5Screate_simple(1, &dims, nullptr));
}
///
/// @brief create a new simple dataspace
///
/// @param[in] dims size of the dataspace in each dimension
/// @param[in] N_dim number of dimensions for the dataspace
/// @return identifier of the new dataspace
///
[[maybe_unused]] static inline auto setup_dataspace(const hsize_t *const dims, const int32_t N_dim = 1) noexcept(false) -> hid_t {
  return (H5Screate_simple(N_dim, dims, nullptr));
}

///
/// @brief close the dataspace
///
/// @param[in] dataspace identifier of the dataspace
///
[[maybe_unused]] static inline auto close_dataspace(const hid_t dataspace) noexcept(false) {
  call(H5Sclose(dataspace));
}

///
/// @brief prepare hyper-slab for 3-dimensional vectors
///
/// @param[in] num number of elements in the target array
///
[[maybe_unused]] static inline auto prepare_hyperslab_Nx3 = [](const auto num) noexcept(false) {
  // setup complete dataspace
  hsize_t dims_Nx3[2] = {num, 3};
  hsize_t dims_Nx2[2] = {num, 2};
  hsize_t dims_Nx1[2] = {num, 1};
  auto dataspace_Nx3 = setup_dataspace(dims_Nx3, 2);
  auto dataspace_Nx2 = setup_dataspace(dims_Nx2, 2);
  auto dataspace_Nx1 = setup_dataspace(dims_Nx1, 2);
  // setup dataspace with blank (x, y; without z)
  auto dataspace_Nx2_3 = setup_dataspace(dims_Nx3, 2);
  hsize_t start[2] = {0, 0};
  hsize_t count[2] = {1, 1};
  call(H5Sselect_hyperslab(dataspace_Nx2_3, H5S_SELECT_SET, start, dims_Nx3, count, dims_Nx2));
  // setup dataspace with blank (z; without x, y)
  auto dataspace_Nx1_3 = setup_dataspace(dims_Nx3, 2);
  start[1] += dims_Nx2[1];
  call(H5Sselect_hyperslab(dataspace_Nx1_3, H5S_SELECT_SET, start, dims_Nx3, count, dims_Nx1));
  // return (std::make_tuple(dataspace_Nx3, dataspace_Nx2, dataspace_Nx1, dataspace_Nx2_3, dataspace_Nx1_3));
  // additional dataspaces for [float double]4
  hsize_t dims_Nx4[2] = {num, 4};
  auto dataspace_Nx4 = setup_dataspace(dims_Nx4, 2);
  // setup dataspace with blank (x, y, z; without w)
  auto dataspace_Nx3_4 = setup_dataspace(dims_Nx4, 2);
  start[1] = 0;
  call(H5Sselect_hyperslab(dataspace_Nx3_4, H5S_SELECT_SET, start, dims_Nx4, count, dims_Nx3));
  // setup dataspace with blank (w; without x, y, z)
  auto dataspace_Nx1_4 = setup_dataspace(dims_Nx4, 2);
  start[1] += dims_Nx3[1];
  call(H5Sselect_hyperslab(dataspace_Nx1_4, H5S_SELECT_SET, start, dims_Nx4, count, dims_Nx1));
  return (std::make_tuple(dataspace_Nx3, dataspace_Nx2, dataspace_Nx1, dataspace_Nx2_3, dataspace_Nx1_3, dataspace_Nx4, dataspace_Nx3_4, dataspace_Nx1_4));
};

///
/// @brief write an attribute (for std::string)
///
/// @param[in] dataspace dataspace for the attribute
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the attribute
/// @param[in] object attribute to be written
///
inline void write_attr(const hid_t dataspace, const hid_t vessel, const char *name, const std::string &object) noexcept(false) {
  const auto datatype = H5Tcopy(H5T_C_S1);
  call(H5Tset_size(datatype, H5T_VARIABLE));
  const auto *const tmp = object.c_str();
  constexpr auto creation_property = H5P_DEFAULT;
  constexpr auto access_property = H5P_DEFAULT;
  const auto attribute = H5Acreate(vessel, name, datatype, dataspace, creation_property, access_property);
  call(H5Awrite(attribute, datatype, &tmp));
  call(H5Aclose(attribute));
  call(H5Tclose(datatype));
}

///
/// @brief write an attribute (as a template function)
///
/// @param[in] dataspace dataspace for the attribute
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the attribute
/// @param[in] object attribute to be written
///
template <class Type>
constexpr void write_attr(const hid_t dataspace, const hid_t vessel, const char *name, const Type *const object) noexcept(false) {
  const auto datatype = h5type(*object);
  constexpr auto creation_property = H5P_DEFAULT;
  constexpr auto access_property = H5P_DEFAULT;
  const auto attribute = H5Acreate(vessel, name, datatype, dataspace, creation_property, access_property);
  call(H5Awrite(attribute, datatype, object));
  call(H5Aclose(attribute));
}

///
/// @brief read an attribute (for std::string)
///
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the attribute
/// @param[in,out] object attribute to be read
///
inline void read_attr(const hid_t vessel, const char *name, std::string &object) noexcept(false) {
  if (H5Aexists(vessel, name) > 0) {
    std::vector<char> val;
    const auto datatype = H5Tcopy(H5T_C_S1);
    call(H5Tset_size(datatype, H5T_VARIABLE));
    constexpr auto access_property = H5P_DEFAULT;
    const auto attribute = H5Aopen(vessel, name, access_property);
    call(H5Aread(attribute, datatype, &val));
    call(H5Aclose(attribute));
    call(H5Tclose(datatype));
    object = val.data();
  }
}

///
/// @brief read an attribute (as a template function)
///
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the attribute
/// @param[in,out] object attribute to be read
///
template <class Type>
constexpr void read_attr(const hid_t vessel, const char *name, Type *const object) noexcept(false) {
  if (H5Aexists(vessel, name) > 0) {
    constexpr auto access_property = H5P_DEFAULT;
    const auto attribute = H5Aopen(vessel, name, access_property);
    call(H5Aread(attribute, h5type(*object), object));
    call(H5Aclose(attribute));
  }
}

///
/// @brief prepare to write dataset in 1D
///
/// @param[in] dims size of the the dataspace
/// @return identifier of the new dataspace and the transfer property list for this I/O operation (compression in this case)
///
auto setup_write1d(hsize_t dims) -> std::pair<hid_t, hid_t>;

///
/// @brief prepare to write dataset in 1D
///
/// @param[in] dims size of the the dataspace
/// @return identifier of the new dataspace and the transfer property list for this I/O operation (compression in this case)
///
auto setup_write2d(hsize_t *dims) -> std::pair<hid_t, hid_t>;

///
/// @brief close writing dataset
///
/// @param[in] dataspace identifier of the dataspace
///
[[maybe_unused]] auto close_write = [](const hid_t dataspace) noexcept(false) {
  call(H5Sclose(dataspace));
};

#ifdef USE_GZIP_COMPRESSION
///
/// @brief close writing dataset
///
/// @param[in] dataspace identifier of the dataspace
/// @param[in] transfer_property identifier of the transfer property list for this I/O operation
///
constexpr auto close_write(const hid_t dataspace, const hid_t transfer_property) noexcept(false) {
  close_write(dataspace);
  call(H5Pclose(transfer_property));
}
#endif  // USE_GZIP_COMPRESSION

///
/// @brief write a dataset
///
/// @param[in] dataspace dataspace
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the dataset
/// @param[in] buffer buffer with data to be written to the file
/// @param[in] transfer_property identifier of the transfer property list for this I/O operation (optional)
/// @param[in] input_datatype identifier of the specified datatype (optional)
/// @param[in] memory_space identifier of the memory dataspace
/// @param[in] file_space identifier of the dataset's dataspace in the file
///
template <class Type>
constexpr void write_data(const hid_t dataspace, const hid_t vessel, const char *name, const Type *const buffer, const hid_t transfer_property = H5P_DEFAULT, const hid_t input_datatype = H5I_UNINIT, const hid_t memory_space = H5S_ALL, const hid_t file_space = H5S_ALL) noexcept(false) {
  const auto memory_datatype = (input_datatype == H5I_UNINIT) ? h5type(*buffer) : input_datatype;
  constexpr auto link_creation = H5P_DEFAULT;
  constexpr auto creation_property = H5P_DEFAULT;
  constexpr auto access_property = H5P_DEFAULT;
  const auto dataset = H5Dcreate(vessel, name, memory_datatype, dataspace, link_creation, creation_property, access_property);
  call(H5Dwrite(dataset, memory_datatype, memory_space, file_space, transfer_property, buffer));
  call(H5Dclose(dataset));
}

///
/// @brief write a dataset
///
/// @param[in] memory_space dataspace in memory
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the dataset
/// @param[in] buffer buffer with data to be written to the file
/// @param[in] start offset of start of hyperslab
/// @param[in] stride hyperslab stride
/// @param[in] count number of blocks included in hyperslab
/// @param[in] block size of block in hyperslab
/// @param[in] file_space dataspace in file
/// @param[in] transfer_property identifier of the transfer property list for this I/O operation (optional)
/// @param[in] input_datatype identifier of the specified datatype (optional)
///
template <class Type>
constexpr void write_data_partial(const hid_t memory_space, const hid_t vessel, const char *name, const Type *const buffer, const hsize_t *const start, const hsize_t *const stride, const hsize_t *const count, const hsize_t *const block, const hid_t file_space, const hid_t transfer_property = H5P_DEFAULT, const hid_t input_datatype = H5I_UNINIT) noexcept(false) {
  // The start, stride, count, and block arrays must be the same size as the rank of the dataspace. For example, if the dataspace is 4-dimensional, each of these parameters must be a 1-dimensional array of size 4.
  call(H5Sselect_hyperslab(memory_space, H5S_SELECT_SET, start, stride, count, block));
  const auto memory_datatype = (input_datatype == H5I_UNINIT) ? h5type(*buffer) : input_datatype;
  write_data(file_space, vessel, name, buffer, transfer_property, memory_datatype, memory_space, file_space);
}

///
/// @brief read a dataset
///
/// @param[in] vessel object identifier (group in most cases)
/// @param[in] name name of the dataset
/// @param[in] buffer dataset to be read
/// @param[in] input_datatype identifier of the specified datatype (optional)
///
template <class Type>
constexpr void read_data(const hid_t vessel, const char *name, Type *const buffer, const hid_t input_datatype = H5I_UNINIT) noexcept(false) {
  constexpr auto link_access_property = H5P_DEFAULT;
  if (H5Lexists(vessel, name, link_access_property)) {
    const auto memory_datatype = (input_datatype == H5I_UNINIT) ? h5type(*buffer) : input_datatype;
    constexpr auto access_property = H5P_DEFAULT;
    const auto dataset = H5Dopen(vessel, name, access_property);
    constexpr auto memory_space = H5S_ALL;
    constexpr auto file_space = H5S_ALL;
    constexpr auto transfer_property = H5P_DEFAULT;
    call(H5Dread(dataset, memory_datatype, memory_space, file_space, transfer_property, buffer));
    call(H5Dclose(dataset));
  }
}
}  // namespace util::hdf5

#endif  // HDF5_HPP
