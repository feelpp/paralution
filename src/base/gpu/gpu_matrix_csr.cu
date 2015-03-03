// **************************************************************************
//
//    PARALUTION   www.paralution.com
//
//    Copyright (C) 2015  PARALUTION Labs UG (haftungsbeschränkt) & Co. KG
//                        Am Hasensprung 6, 76571 Gaggenau
//                        Handelsregister: Amtsgericht Mannheim, HRA 706051
//                        Vertreten durch:
//                        PARALUTION Labs Verwaltungs UG (haftungsbeschränkt)
//                        Am Hasensprung 6, 76571 Gaggenau
//                        Handelsregister: Amtsgericht Mannheim, HRB 721277
//                        Geschäftsführer: Dimitar Lukarski, Nico Trost
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// **************************************************************************



// PARALUTION version 1.0.0 


#include "../../utils/def.hpp"
#include "gpu_matrix_csr.hpp"
#include "gpu_matrix_coo.hpp"
#include "gpu_matrix_dia.hpp"
#include "gpu_matrix_ell.hpp"
#include "gpu_matrix_hyb.hpp"
#include "gpu_matrix_mcsr.hpp"
#include "gpu_matrix_bcsr.hpp"
#include "gpu_matrix_dense.hpp"
#include "gpu_vector.hpp"
#include "../host/host_matrix_csr.hpp"
#include "../base_matrix.hpp"
#include "../base_vector.hpp"
#include "../backend_manager.hpp"
#include "../../utils/log.hpp"
#include "../../utils/allocate_free.hpp"
#include "gpu_utils.hpp"
#include "cuda_kernels_general.hpp"
#include "cuda_kernels_csr.hpp"
#include "cuda_kernels_vector.hpp"
#include "cusparse_csr.hpp"
#include "gpu_allocate_free.hpp"
#include "../matrix_formats_ind.hpp"

#include <cuda.h>
#include <cusparse_v2.h>

namespace paralution {

template <typename ValueType>
GPUAcceleratorMatrixCSR<ValueType>::GPUAcceleratorMatrixCSR() {

  // no default constructors
  LOG_INFO("no default constructor");
  FATAL_ERROR(__FILE__, __LINE__);

}

template <typename ValueType>
GPUAcceleratorMatrixCSR<ValueType>::GPUAcceleratorMatrixCSR(const Paralution_Backend_Descriptor local_backend) {

  LOG_DEBUG(this, "GPUAcceleratorMatrixCSR::GPUAcceleratorMatrixCSR()",
            "constructor with local_backend");

  this->mat_.row_offset = NULL;
  this->mat_.col        = NULL;
  this->mat_.val        = NULL;
  this->set_backend(local_backend);

  this->L_mat_descr_ = 0;
  this->U_mat_descr_ = 0;

  this->L_mat_info_ = 0;
  this->U_mat_info_ = 0;

  this->mat_descr_ = 0;

  this->tmp_vec_ = NULL;

  CHECK_CUDA_ERROR(__FILE__, __LINE__);

  cusparseStatus_t stat_t;
  
  stat_t = cusparseCreateMatDescr(&this->mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);
  
  stat_t = cusparseSetMatIndexBase(this->mat_descr_, CUSPARSE_INDEX_BASE_ZERO);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);
  
  stat_t = cusparseSetMatType(this->mat_descr_, CUSPARSE_MATRIX_TYPE_GENERAL);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <typename ValueType>
GPUAcceleratorMatrixCSR<ValueType>::~GPUAcceleratorMatrixCSR() {

  LOG_DEBUG(this, "GPUAcceleratorMatrixCSR::~GPUAcceleratorMatrixCSR()",
            "destructor");

  this->Clear();

  cusparseStatus_t stat_t;

  stat_t = cusparseDestroyMatDescr(this->mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::info(void) const {

  LOG_INFO("GPUAcceleratorMatrixCSR<ValueType>");

}


template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::AllocateCSR(const int nnz, const int nrow, const int ncol) {

  assert(nnz >= 0);
  assert(ncol >= 0);
  assert(nrow >= 0);

  if (this->get_nnz() > 0)
    this->Clear();

  if (nnz > 0) {

    allocate_gpu(nrow+1, &this->mat_.row_offset);
    allocate_gpu(nnz,    &this->mat_.col);
    allocate_gpu(nnz,    &this->mat_.val);
    
    set_to_zero_gpu(this->local_backend_.GPU_block_size, 
                    this->local_backend_.GPU_max_threads,
                    nrow+1, mat_.row_offset);
    set_to_zero_gpu(this->local_backend_.GPU_block_size, 
                    this->local_backend_.GPU_max_threads,
                    nnz, mat_.col);
    set_to_zero_gpu(this->local_backend_.GPU_block_size, 
                    this->local_backend_.GPU_max_threads,
                    nnz, mat_.val);

    this->nrow_ = nrow;
    this->ncol_ = ncol;
    this->nnz_  = nnz;

  }

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::SetDataPtrCSR(int **row_offset, int **col, ValueType **val,
                                                       const int nnz, const int nrow, const int ncol) {

  assert(*row_offset != NULL);
  assert(*col != NULL);
  assert(*val != NULL);
  assert(nnz > 0);
  assert(nrow > 0);
  assert(ncol > 0);

  this->Clear();

  this->nrow_ = nrow;
  this->ncol_ = ncol;
  this->nnz_  = nnz;

  cudaDeviceSynchronize();

  this->mat_.row_offset = *row_offset;
  this->mat_.col = *col;
  this->mat_.val = *val;

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::LeaveDataPtrCSR(int **row_offset, int **col, ValueType **val) {

  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);
  assert(this->get_nnz() > 0);

  cudaDeviceSynchronize();

  // see free_host function for details
  *row_offset = this->mat_.row_offset;
  *col = this->mat_.col;
  *val = this->mat_.val;

  this->mat_.row_offset = NULL;
  this->mat_.col = NULL;
  this->mat_.val = NULL;

  this->nrow_ = 0;
  this->ncol_ = 0;
  this->nnz_  = 0;

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::Clear() {

  if (this->get_nnz() > 0) {

    free_gpu(&this->mat_.row_offset);
    free_gpu(&this->mat_.col);
    free_gpu(&this->mat_.val);

    this->nrow_ = 0;
    this->ncol_ = 0;
    this->nnz_  = 0;

    this->LUAnalyseClear();
    this->LLAnalyseClear();

  }

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::Zeros() {

  if (this->get_nnz() > 0)
    set_to_zero_gpu(this->local_backend_.GPU_block_size,
                    this->local_backend_.GPU_max_threads,
                    this->get_nnz(), mat_.val);

  return true;

}


template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyFromHost(const HostMatrix<ValueType> &src) {

  const HostMatrixCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // CPU to GPU copy
  if ((cast_mat = dynamic_cast<const HostMatrixCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );

    assert(this->get_nnz()  == src.get_nnz());
    assert(this->get_nrow() == src.get_nrow());
    assert(this->get_ncol() == src.get_ncol());
  
    if (this->get_nnz() > 0) {

      cudaMemcpy(this->mat_.row_offset,     // dst
                 cast_mat->mat_.row_offset, // src
                 (this->get_nrow()+1)*sizeof(int), // size
                 cudaMemcpyHostToDevice);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpy(this->mat_.col,     // dst
                 cast_mat->mat_.col, // src
                 this->get_nnz()*sizeof(int), // size
                 cudaMemcpyHostToDevice);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpy(this->mat_.val,     // dst
                 cast_mat->mat_.val, // src
                 this->get_nnz()*sizeof(ValueType), // size
                 cudaMemcpyHostToDevice);    
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
    }
    
  } else {
    
    LOG_INFO("Error unsupported GPU matrix type");
    this->info();
    src.info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyFromHostAsync(const HostMatrix<ValueType> &src) {

  const HostMatrixCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // CPU to GPU copy
  if ((cast_mat = dynamic_cast<const HostMatrixCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );

    assert(this->get_nnz()  == src.get_nnz());
    assert(this->get_nrow() == src.get_nrow());
    assert(this->get_ncol() == src.get_ncol());
  
    if (this->get_nnz() > 0) {

      cudaMemcpyAsync(this->mat_.row_offset,     // dst
                 cast_mat->mat_.row_offset, // src
                 (this->get_nrow()+1)*sizeof(int), // size
                 cudaMemcpyHostToDevice);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpyAsync(this->mat_.col,     // dst
                 cast_mat->mat_.col, // src
                 this->get_nnz()*sizeof(int), // size
                 cudaMemcpyHostToDevice);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpyAsync(this->mat_.val,     // dst
                 cast_mat->mat_.val, // src
                 this->get_nnz()*sizeof(ValueType), // size
                 cudaMemcpyHostToDevice);    
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
    }
    
  } else {
    
    LOG_INFO("Error unsupported GPU matrix type");
    this->info();
    src.info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyToHost(HostMatrix<ValueType> *dst) const {

  HostMatrixCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // GPU to CPU copy
  if ((cast_mat = dynamic_cast<HostMatrixCSR<ValueType>*> (dst)) != NULL) {

    cast_mat->set_backend(this->local_backend_);   

  if (dst->get_nnz() == 0)
    cast_mat->AllocateCSR(this->get_nnz(), this->get_nrow(), this->get_ncol() );

    assert(this->get_nnz()  == dst->get_nnz());
    assert(this->get_ncol() == dst->get_ncol());

   
    if (this->get_nnz() > 0) {

      cudaMemcpy(cast_mat->mat_.row_offset, // dst
                 this->mat_.row_offset,     // src
                 (this->get_nrow()+1)*sizeof(int), // size
                 cudaMemcpyDeviceToHost);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpy(cast_mat->mat_.col, // dst
                 this->mat_.col,     // src
                 this->get_nnz()*sizeof(int), // size
                 cudaMemcpyDeviceToHost);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpy(cast_mat->mat_.val, // dst
                 this->mat_.val,     // src
                 this->get_nnz()*sizeof(ValueType), // size
                 cudaMemcpyDeviceToHost);    
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
    }

    
  } else {
    
    LOG_INFO("Error unsupported GPU matrix type");
    this->info();
    dst->info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}


template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyToHostAsync(HostMatrix<ValueType> *dst) const {

  HostMatrixCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // GPU to CPU copy
  if ((cast_mat = dynamic_cast<HostMatrixCSR<ValueType>*> (dst)) != NULL) {

    cast_mat->set_backend(this->local_backend_);   

  if (dst->get_nnz() == 0)
    cast_mat->AllocateCSR(this->get_nnz(), this->get_nrow(), this->get_ncol() );

    assert(this->get_nnz()  == dst->get_nnz());
    assert(this->get_ncol() == dst->get_ncol());
   
    if (this->get_nnz() > 0) {

      cudaMemcpyAsync(cast_mat->mat_.row_offset, // dst
                 this->mat_.row_offset,     // src
                 (this->get_nrow()+1)*sizeof(int), // size
                 cudaMemcpyDeviceToHost);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpyAsync(cast_mat->mat_.col, // dst
                 this->mat_.col,     // src
                 this->get_nnz()*sizeof(int), // size
                 cudaMemcpyDeviceToHost);
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      
      cudaMemcpyAsync(cast_mat->mat_.val, // dst
                 this->mat_.val,     // src
                 this->get_nnz()*sizeof(ValueType), // size
                 cudaMemcpyDeviceToHost);    
      CHECK_CUDA_ERROR(__FILE__, __LINE__);     
    }

    
  } else {
    
    LOG_INFO("Error unsupported GPU matrix type");
    this->info();
    dst->info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}


template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyFrom(const BaseMatrix<ValueType> &src) {

  const GPUAcceleratorMatrixCSR<ValueType> *gpu_cast_mat;
  const HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // GPU to GPU copy
  if ((gpu_cast_mat = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );


     assert(this->get_nnz()  == src.get_nnz());
     assert(this->get_nrow() == src.get_nrow());
     assert(this->get_ncol() == src.get_ncol());


    if (this->get_nnz() > 0) {

        cudaMemcpy(this->mat_.row_offset,         // dst
                   gpu_cast_mat->mat_.row_offset, // src
                   (this->get_nrow()+1)*sizeof(int), // size
                   cudaMemcpyDeviceToDevice);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(this->mat_.col,         // dst
                   gpu_cast_mat->mat_.col, // src
                   this->get_nnz()*sizeof(int), // size
                   cudaMemcpyDeviceToDevice);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(this->mat_.val,         // dst
                   gpu_cast_mat->mat_.val, // src
                   this->get_nnz()*sizeof(ValueType), // size
                   cudaMemcpyDeviceToDevice);    
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      }

  } else {

    //CPU to GPU
    if ((host_cast_mat = dynamic_cast<const HostMatrix<ValueType>*> (&src)) != NULL) {
      
      this->CopyFromHost(*host_cast_mat);
      
    } else {
      
      LOG_INFO("Error unsupported GPU matrix type");
      this->info();
      src.info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }
    
  }

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyFromAsync(const BaseMatrix<ValueType> &src) {

  const GPUAcceleratorMatrixCSR<ValueType> *gpu_cast_mat;
  const HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // GPU to GPU copy
  if ((gpu_cast_mat = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );


     assert(this->get_nnz()  == src.get_nnz());
     assert(this->get_nrow() == src.get_nrow());
     assert(this->get_ncol() == src.get_ncol());


    if (this->get_nnz() > 0) {

        cudaMemcpy(this->mat_.row_offset,         // dst
                   gpu_cast_mat->mat_.row_offset, // src
                   (this->get_nrow()+1)*sizeof(int), // size
                   cudaMemcpyDeviceToDevice);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(this->mat_.col,         // dst
                   gpu_cast_mat->mat_.col, // src
                   this->get_nnz()*sizeof(int), // size
                   cudaMemcpyDeviceToDevice);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(this->mat_.val,         // dst
                   gpu_cast_mat->mat_.val, // src
                   this->get_nnz()*sizeof(ValueType), // size
                   cudaMemcpyDeviceToDevice);    
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      }

  } else {

    //CPU to GPU
    if ((host_cast_mat = dynamic_cast<const HostMatrix<ValueType>*> (&src)) != NULL) {
      
      this->CopyFromHostAsync(*host_cast_mat);
      
    } else {
      
      LOG_INFO("Error unsupported GPU matrix type");
      this->info();
      src.info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }
    
  }

}


template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyTo(BaseMatrix<ValueType> *dst) const {

  GPUAcceleratorMatrixCSR<ValueType> *gpu_cast_mat;
  HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // GPU to GPU copy
  if ((gpu_cast_mat = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (dst)) != NULL) {

    gpu_cast_mat->set_backend(this->local_backend_);       

  if (this->get_nnz() == 0)
    gpu_cast_mat->AllocateCSR(dst->get_nnz(), dst->get_nrow(), dst->get_ncol() );

    assert(this->get_nnz()  == dst->get_nnz());
    assert(this->get_nrow() == dst->get_nrow());
    assert(this->get_ncol() == dst->get_ncol());

    if (this->get_nnz() > 0) {

        cudaMemcpy(gpu_cast_mat->mat_.row_offset, // dst
                   this->mat_.row_offset,         // src
                   (this->get_nrow()+1)*sizeof(int), // size
                   cudaMemcpyDeviceToHost);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(gpu_cast_mat->mat_.col, // dst
                   this->mat_.col,         // src
                   this->get_nnz()*sizeof(int), // size
                   cudaMemcpyDeviceToHost);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(gpu_cast_mat->mat_.val, // dst
                   this->mat_.val,         // src
                   this->get_nnz()*sizeof(ValueType), // size
                   cudaMemcpyDeviceToHost);    
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      }
    
  } else {

    //GPU to CPU
    if ((host_cast_mat = dynamic_cast<HostMatrix<ValueType>*> (dst)) != NULL) {
      
      this->CopyToHost(host_cast_mat);

    } else {
      
      LOG_INFO("Error unsupported GPU matrix type");
      this->info();
      dst->info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }

  }


}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyToAsync(BaseMatrix<ValueType> *dst) const {

  GPUAcceleratorMatrixCSR<ValueType> *gpu_cast_mat;
  HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // GPU to GPU copy
  if ((gpu_cast_mat = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (dst)) != NULL) {

    gpu_cast_mat->set_backend(this->local_backend_);       

  if (this->get_nnz() == 0)
    gpu_cast_mat->AllocateCSR(dst->get_nnz(), dst->get_nrow(), dst->get_ncol() );

    assert(this->get_nnz()  == dst->get_nnz());
    assert(this->get_nrow() == dst->get_nrow());
    assert(this->get_ncol() == dst->get_ncol());


    if (this->get_nnz() > 0) {

        cudaMemcpy(gpu_cast_mat->mat_.row_offset, // dst
                   this->mat_.row_offset,         // src
                   (this->get_nrow()+1)*sizeof(int), // size
                   cudaMemcpyDeviceToHost);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(gpu_cast_mat->mat_.col, // dst
                   this->mat_.col,         // src
                   this->get_nnz()*sizeof(int), // size
                   cudaMemcpyDeviceToHost);
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
        
        cudaMemcpy(gpu_cast_mat->mat_.val, // dst
                   this->mat_.val,         // src
                   this->get_nnz()*sizeof(ValueType), // size
                   cudaMemcpyDeviceToHost);    
        CHECK_CUDA_ERROR(__FILE__, __LINE__);     
      }
    
  } else {

    //GPU to CPU
    if ((host_cast_mat = dynamic_cast<HostMatrix<ValueType>*> (dst)) != NULL) {
      
      this->CopyToHostAsync(host_cast_mat);

    } else {
      
      LOG_INFO("Error unsupported GPU matrix type");
      this->info();
      dst->info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }

  }


}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyFromCSR(const int *row_offsets, const int *col, const ValueType *val) {

  // assert CSR format
  assert(this->get_mat_format() == CSR);

  if (this->get_nnz() > 0) {

    assert(this->nrow_ > 0);
    assert(this->ncol_ > 0);

    cudaMemcpy(this->mat_.row_offset,            // dst
               row_offsets,                      // src
               (this->get_nrow()+1)*sizeof(int), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    cudaMemcpy(this->mat_.col,              // dst
               col,                         // src
               this->get_nnz()*sizeof(int), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    cudaMemcpy(this->mat_.val,                    // dst
               val,                               // src
               this->get_nnz()*sizeof(ValueType), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::CopyToCSR(int *row_offsets, int *col, ValueType *val) const {

  // assert CSR format
  assert(this->get_mat_format() == CSR);

  if (this->get_nnz() > 0) {

    assert(this->nrow_ > 0);
    assert(this->ncol_ > 0);

    cudaMemcpy(row_offsets,                      // dst
               this->mat_.row_offset,            // src
               (this->get_nrow()+1)*sizeof(int), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    cudaMemcpy(col,                         // dst
               this->mat_.col,              // src
               this->get_nnz()*sizeof(int), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    cudaMemcpy(val,                               // dst
               this->mat_.val,                    // src
               this->get_nnz()*sizeof(ValueType), // size
               cudaMemcpyDeviceToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ConvertFrom(const BaseMatrix<ValueType> &mat) {

  this->Clear();

  // empty matrix is empty matrix
  if (mat.get_nnz() == 0)
    return true;

  const GPUAcceleratorMatrixCSR<ValueType>   *cast_mat_csr;
  if ((cast_mat_csr = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&mat)) != NULL) {
    
    this->CopyFrom(*cast_mat_csr);
    return true;
    
  }

  /*
  const GPUAcceleratorMatrixCOO<ValueType>   *cast_mat_coo;
  if ((cast_mat_coo = dynamic_cast<const GPUAcceleratorMatrixCOO<ValueType>*> (&mat)) != NULL) {

    this->Clear();


  TODO
  Allocate
  copy colmn
  copy val
  cusparseStatus_t
      cusparseXcoo2csr(cusparseHandle_t handle, const int *cooRowInd,
                       int nnz, int m, int *csrRowPtr, cusparseIndexBase_t
                       idxBase);


    FATAL_ERROR(__FILE__, __LINE__);

    this->nrow_ = cast_mat_coo->get_nrow();
    this->ncol_ = cast_mat_coo->get_ncol();
    this->nnz_  = cast_mat_coo->get_nnz();

    return true;

  }
  */

  /*
  const GPUAcceleratorMatrixDENSE<ValueType> *cast_mat_dense;
  if ((cast_mat_dense = dynamic_cast<const GPUAcceleratorMatrixDENSE<ValueType>*> (&mat)) != NULL) {

    this->Clear();
    int nnz = 0;

    FATAL_ERROR(__FILE__, __LINE__);

    this->nrow_ = cast_mat_dense->get_nrow();
    this->ncol_ = cast_mat_dense->get_ncol();
    this->nnz_  = nnz;

    return true;

  }
  */

  /*
  const GPUAcceleratorMatrixDIA<ValueType>   *cast_mat_dia;
  if ((cast_mat_dia = dynamic_cast<const GPUAcceleratorMatrixDIA<ValueType>*> (&mat)) != NULL) {

    this->Clear();
    int nnz = 0;

    FATAL_ERROR(__FILE__, __LINE__);

    this->nrow_ = cast_mat_dia->get_nrow();
    this->ncol_ = cast_mat_dia->get_ncol();
    this->nnz_  = nnz ;

    return true;

  }
  */

  /*
  const GPUAcceleratorMatrixELL<ValueType>   *cast_mat_ell;
  if ((cast_mat_ell = dynamic_cast<const GPUAcceleratorMatrixELL<ValueType>*> (&mat)) != NULL) {

    this->Clear();
    int nnz = 0;

    FATAL_ERROR(__FILE__, __LINE__);

    this->nrow_ = cast_mat_ell->get_nrow();
    this->ncol_ = cast_mat_ell->get_ncol();
    this->nnz_  = nnz ;

    return true;

  }
  */

  /*
  const GPUAcceleratorMatrixMCSR<ValueType>  *cast_mat_mcsr;
  if ((cast_mat_mcsr = dynamic_cast<const GPUAcceleratorMatrixMCSR<ValueType>*> (&mat)) != NULL) {

    this->Clear();

    FATAL_ERROR(__FILE__, __LINE__);

    this->nrow_ = cast_mat_mcsr->get_nrow();
    this->ncol_ = cast_mat_mcsr->get_ncol();
    this->nnz_  = cast_mat_mcsr->get_nnz();

    return true;

  }
  */


  /*
  const GPUAcceleratorMatrixHYB<ValueType>   *cast_mat_hyb;
  if ((cast_mat_hyb = dynamic_cast<const GPUAcceleratorMatrixHYB<ValueType>*> (&mat)) != NULL) {

    this->Clear();

    FATAL_ERROR(__FILE__, __LINE__);
    int nnz = 0;

    this->nrow_ = cast_mat_hyb->get_nrow();
    this->ncol_ = cast_mat_hyb->get_ncol();
    this->nnz_  = nnz;

    return true;

  }
  */


  return false;

}


template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::Permute( const BaseVector<int> &permutation){

  assert(&permutation != NULL);
  assert(permutation.get_size() == this->get_nrow());
  assert(permutation.get_size() == this->get_ncol());

  if (this->get_nnz() > 0) {

    int *d_nnzr     = NULL;
    int *d_nnzrPerm = NULL;
    int *d_nnzPerm  = NULL;
    int *d_offset   = NULL;
    ValueType *d_data = NULL;

    allocate_gpu<int>(this->get_nrow(), &d_nnzr);
    allocate_gpu<int>(this->get_nrow(), &d_nnzrPerm);
    allocate_gpu<int>((this->get_nrow()+1), &d_nnzPerm);
    allocate_gpu<ValueType>(this->get_nnz(), &d_data);
    allocate_gpu<int>(this->get_nnz(), &d_offset);

    const GPUAcceleratorVector<int> *cast_perm = dynamic_cast<const GPUAcceleratorVector<int>*> (&permutation);
    assert(cast_perm != NULL);

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_calc_row_nnz<int> <<< GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset, d_nnzr);
    CHECK_CUDA_ERROR(__FILE__,__LINE__);

    kernel_permute_row_nnz<int> <<< GridSize, BlockSize>>>(this->get_nrow(), d_nnzr, cast_perm->vec_, d_nnzrPerm);
    CHECK_CUDA_ERROR(__FILE__,__LINE__);

    //TODO 
    //move in extra file
    cum_sum<int, 256>(d_nnzPerm, d_nnzrPerm, this->get_nrow());

    kernel_permute_rows<ValueType, int> <<<GridSize, BlockSize>>>(
                    this->get_nrow(), 
                    this->mat_.row_offset,
                    d_nnzPerm,
                    this->mat_.col,
                    this->mat_.val,
                    cast_perm->vec_,
                    d_nnzr,
                    d_offset,
                    d_data);
    CHECK_CUDA_ERROR(__FILE__,__LINE__);

    free_gpu<int>(&this->mat_.row_offset);	

    this->mat_.row_offset = d_nnzPerm;

    int *d_buffer = NULL;
    int *h_buffer = NULL;
    int GROUP_SIZE;
    int LOCAL_SIZE;
    int FinalReduceSize;

    allocate_gpu<int>(this->local_backend_.GPU_warp * 4, &d_buffer);

    dim3 BlockSize2(this->local_backend_.GPU_block_size);
    dim3 GridSize2(this->local_backend_.GPU_warp * 4);

    GROUP_SIZE = ( size_t( ( size_t( nrow / ( this->local_backend_.GPU_warp * 4 ) ) + 1 ) 
                 / this->local_backend_.GPU_block_size ) + 1 ) * this->local_backend_.GPU_block_size;
    LOCAL_SIZE = GROUP_SIZE / this->local_backend_.GPU_block_size;

    kernel_max<int, int, 256> <<<GridSize2, BlockSize2>>> (nrow, d_nnzr, d_buffer, GROUP_SIZE, LOCAL_SIZE);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    FinalReduceSize = this->local_backend_.GPU_warp * 4;
    allocate_host(FinalReduceSize, &h_buffer);

    cudaMemcpy(h_buffer, // dst
               d_buffer, // src
               FinalReduceSize*sizeof(int), // size
               cudaMemcpyDeviceToHost);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    free_gpu<int>(&d_buffer);

    int maxnnzrow = 0;
    for (int i=0; i<FinalReduceSize; ++i)
      if (maxnnzrow < h_buffer[i])
        maxnnzrow = h_buffer[i];

    free_host(&h_buffer);

    //TODO what should happen in this case??
    if (maxnnzrow > 1024)
      return false;
    else if (maxnnzrow > 512)
      kernel_permute_cols<ValueType, int, 1024> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                         cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                         d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow > 256)
      kernel_permute_cols<ValueType, int, 512> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                         cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                         d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow > 128)
      kernel_permute_cols<ValueType, int, 256> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                         cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                         d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow >  64)
      kernel_permute_cols<ValueType, int, 128> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                         cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                         d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow >  32)
      kernel_permute_cols<ValueType, int, 64> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                        cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                        d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow >  16)
      kernel_permute_cols<ValueType, int, 32> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                        cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                        d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow >   8)
      kernel_permute_cols<ValueType, int, 16> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                        cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                        d_data, this->mat_.col, this->mat_.val);
    else if (maxnnzrow >   4)
      kernel_permute_cols<ValueType, int, 8> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                       cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                       d_data, this->mat_.col, this->mat_.val);
    else
      kernel_permute_cols<ValueType, int, 4> <<<GridSize, BlockSize>>>(this->get_nrow(), this->mat_.row_offset,
                                                                       cast_perm->vec_, d_nnzrPerm, d_offset,
                                                                       d_data, this->mat_.col, this->mat_.val);
    CHECK_CUDA_ERROR(__FILE__,__LINE__);

    free_gpu<int>(&d_offset);
    free_gpu<ValueType>(&d_data);
    free_gpu<int>(&d_nnzrPerm);
    free_gpu<int>(&d_nnzr);

  }

  return true;

}

template <>
void GPUAcceleratorMatrixCSR<float>::Apply(const BaseVector<float> &in, BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->get_ncol());
    assert(out->get_size() == this->get_nrow());
    
    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in) ; 
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out) ; 
    
    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;
    const float scalar = 1.0;
    const float beta = 0.0;

    stat_t = cusparseScsrmv(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                            CUSPARSE_OPERATION_NON_TRANSPOSE,
                            this->get_nrow(), this->get_ncol(), this->get_nnz(), &scalar,
                            this->mat_descr_,
                            this->mat_.val, this->mat_.row_offset, this->mat_.col,
                            cast_in->vec_, &beta,
                            cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

/*
    // Using cusparse instead...
    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
    
    kernel_csr_spmv_scalar<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                      cast_in->vec_, cast_out->vec_);
    
    CHECK_CUDA_ERROR(__FILE__, __LINE__);      
*/
  }
    
}

template <>
void GPUAcceleratorMatrixCSR<double>::Apply(const BaseVector<double> &in, BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->get_ncol());
    assert(out->get_size() == this->get_nrow());
    
    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in) ; 
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out) ; 
    
    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;
    const double scalar = 1.0;
    const double beta = 0.0;

    stat_t = cusparseDcsrmv(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                            CUSPARSE_OPERATION_NON_TRANSPOSE,
                            this->get_nrow(), this->get_ncol(), this->get_nnz(), &scalar,
                            this->mat_descr_,
                            this->mat_.val, 
                            this->mat_.row_offset, this->mat_.col,
                            cast_in->vec_, &beta,
                            cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    /*
    // Using cusparse instead...
    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_spmv_scalar<double, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                      cast_in->vec_, cast_out->vec_);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);
    */
  }
    
}

template <>
void GPUAcceleratorMatrixCSR<float>::ApplyAdd(const BaseVector<float> &in, const float scalar,
                                                    BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->get_ncol());
    assert(out->get_size() == this->get_nrow());

    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in);
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;
    const float beta = 1.0;

    stat_t = cusparseScsrmv(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                            CUSPARSE_OPERATION_NON_TRANSPOSE,
                            this->get_nrow(), this->get_ncol(), this->get_nnz(), &scalar,
                            this->mat_descr_,
                            this->mat_.val, this->mat_.row_offset, this->mat_.col,
                            cast_in->vec_, &beta,
                            cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

/*
    // Using cusparse now...
    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
    
    kernel_csr_add_spmv_scalar<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                          scalar, cast_in->vec_, cast_out->vec_);
    
    CHECK_CUDA_ERROR(__FILE__, __LINE__);    
*/  
  }

}

template <>
void GPUAcceleratorMatrixCSR<double>::ApplyAdd(const BaseVector<double> &in, const double scalar,
                                                     BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->get_ncol());
    assert(out->get_size() == this->get_nrow());

    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in);
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;
    const double beta = 1.0;

    stat_t = cusparseDcsrmv(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                            CUSPARSE_OPERATION_NON_TRANSPOSE,
                            this->get_nrow(), this->get_ncol(), this->get_nnz(), &scalar,
                            this->mat_descr_,
                            this->mat_.val, this->mat_.row_offset, this->mat_.col,
                            cast_in->vec_, &beta,
                            cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    /*
    // Using cusparse now...
    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
    
    kernel_csr_add_spmv_scalar<double, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                          scalar, cast_in->vec_, cast_out->vec_);
    
    CHECK_CUDA_ERROR(__FILE__, __LINE__);    
    */

  }

}

template <>
bool GPUAcceleratorMatrixCSR<float>::ILU0Factorize(void) {
  
  if (this->get_nnz() > 0) {

    cusparseStatus_t stat_t;

    cusparseSolveAnalysisInfo_t infoA = 0;

    stat_t = cusparseCreateSolveAnalysisInfo(&infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsrilu0(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                              CUSPARSE_OPERATION_NON_TRANSPOSE,
                              this->get_nrow(),
                              this->mat_descr_,
                              this->mat_.val, this->mat_.row_offset, this->mat_.col,
                              infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDestroySolveAnalysisInfo(infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::ILU0Factorize(void) {

  if (this->get_nnz() > 0) {

    cusparseStatus_t stat_t;

    cusparseSolveAnalysisInfo_t infoA = 0;

    stat_t = cusparseCreateSolveAnalysisInfo(&infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsrilu0(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                              CUSPARSE_OPERATION_NON_TRANSPOSE,
                              this->get_nrow(),
                              this->mat_descr_,
                              this->mat_.val, this->mat_.row_offset, this->mat_.col,
                              infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDestroySolveAnalysisInfo(infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::ICFactorize(BaseVector<float> *inv_diag) {

  if (this->get_nnz() > 0) {

    cusparseStatus_t stat_t;

    cusparseSolveAnalysisInfo_t infoA = 0;

    stat_t = cusparseCreateSolveAnalysisInfo(&infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->mat_descr_, CUSPARSE_MATRIX_TYPE_SYMMETRIC);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle), 
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col, 
                                     infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsric0(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                             CUSPARSE_OPERATION_NON_TRANSPOSE,
                             this->get_nrow(),
                             this->mat_descr_,
                             this->mat_.val, this->mat_.row_offset, this->mat_.col,
                             infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::ICFactorize(BaseVector<double> *inv_diag) {

  if (this->get_nnz() > 0) {

    cusparseStatus_t stat_t;

    cusparseSolveAnalysisInfo_t infoA = 0;

    stat_t = cusparseCreateSolveAnalysisInfo(&infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->mat_descr_, CUSPARSE_MATRIX_TYPE_SYMMETRIC);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle), 
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col, 
                                     infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsric0(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                             CUSPARSE_OPERATION_NON_TRANSPOSE,
                             this->get_nrow(),
                             this->mat_descr_,
                             this->mat_.val, this->mat_.row_offset, this->mat_.col,
                             infoA);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
void GPUAcceleratorMatrixCSR<double>::LUAnalyse(void) {

    this->LUAnalyseClear();

    cusparseStatus_t stat_t;

    // L part
    stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);


    // U part
    stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_UPPER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Analysis
    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->L_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE, 
                                     this->get_nrow(), this->get_nnz(), 
                                     this->U_mat_descr_, 
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    assert(this->get_ncol() == this->get_nrow());
    assert(this->tmp_vec_ == NULL);
    this->tmp_vec_ = new GPUAcceleratorVector<double>(this->local_backend_);
    assert(this->tmp_vec_ != NULL);

    tmp_vec_->Allocate(this->get_nrow());

}

template <>
void GPUAcceleratorMatrixCSR<float>::LUAnalyse(void) {

    this->LUAnalyseClear();

    cusparseStatus_t stat_t;

    // L part
    stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);


    // U part
    stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_UPPER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Analysis
    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->L_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE, 
                                     this->get_nrow(), this->get_nnz(), 
                                     this->U_mat_descr_, 
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    assert(this->get_ncol() == this->get_nrow());
    assert(this->tmp_vec_ == NULL);
    this->tmp_vec_ = new GPUAcceleratorVector<float>(this->local_backend_);
    assert(this->tmp_vec_ != NULL);

    tmp_vec_->Allocate(this->get_nrow());

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::LUAnalyseClear(void) {

  cusparseStatus_t stat_t;

  if (this->L_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->L_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->U_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->U_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  this->L_mat_descr_ = 0;
  this->U_mat_descr_ = 0;
  this->L_mat_info_ = 0;
  this->U_mat_info_ = 0;

  if (this ->tmp_vec_ != NULL) {
    delete this->tmp_vec_ ;
    this->tmp_vec_ = NULL;
  }

}

template <>
bool GPUAcceleratorMatrixCSR<float>::LUSolve(const BaseVector<float> &in, BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    assert(this->tmp_vec_ != NULL);

    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in);
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    float one = float(1.0);

    // Solve L
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  tmp_vec_->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Solve U
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  tmp_vec_->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::LUSolve(const BaseVector<double> &in, BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in);
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    double one = double(1.0);

    // Solve L
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  this->tmp_vec_->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Solve U
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  this->tmp_vec_->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
void GPUAcceleratorMatrixCSR<double>::LLAnalyse(void) {

    this->LLAnalyseClear();

    cusparseStatus_t stat_t;

    // L part
    stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_TRIANGULAR);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // U part
    stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_TRIANGULAR);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Analysis
    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->L_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->U_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    assert(this->get_ncol() == this->get_nrow());
    assert(this->tmp_vec_ == NULL);
    this->tmp_vec_ = new GPUAcceleratorVector<double>(this->local_backend_);
    assert(this->tmp_vec_ != NULL);

    tmp_vec_->Allocate(this->get_nrow());

}

template <>
void GPUAcceleratorMatrixCSR<float>::LLAnalyse(void) {

    this->LLAnalyseClear();

    cusparseStatus_t stat_t;

    // L part
    stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_TRIANGULAR);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // U part
    stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_TRIANGULAR);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Analysis
    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_NON_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->L_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                     CUSPARSE_OPERATION_TRANSPOSE,
                                     this->get_nrow(), this->get_nnz(),
                                     this->U_mat_descr_,
                                     this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                     this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    assert(this->get_ncol() == this->get_nrow());
    assert(this->tmp_vec_ == NULL);
    this->tmp_vec_ = new GPUAcceleratorVector<float>(this->local_backend_);
    assert(this->tmp_vec_ != NULL);

    tmp_vec_->Allocate(this->get_nrow());

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::LLAnalyseClear(void) {

  cusparseStatus_t stat_t;

  if (this->L_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->L_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->U_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->U_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  this->L_mat_descr_ = 0;
  this->U_mat_descr_ = 0;
  this->L_mat_info_ = 0;
  this->U_mat_info_ = 0;

  if (this ->tmp_vec_ != NULL) {
    delete this->tmp_vec_ ;
    this->tmp_vec_ = NULL;
  }
    

}

template <>
bool GPUAcceleratorMatrixCSR<double>::LLSolve(const BaseVector<double> &in, BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in);
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    double one = double(1.0);

    // Solve L
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  this->tmp_vec_->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Solve U
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  this->tmp_vec_->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::LLSolve(const BaseVector<float> &in, BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in);
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    float one = float(1.0);

    // Solve L
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  this->tmp_vec_->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

    // Solve U
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  this->tmp_vec_->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::LLSolve(const BaseVector<ValueType> &in, const BaseVector<ValueType> &inv_diag,
                                                 BaseVector<ValueType> *out) const {

  return LLSolve(in, out);

}

template <>
void GPUAcceleratorMatrixCSR<double>::LAnalyse(const bool diag_unit) {

  cusparseStatus_t stat_t;

  // L part
  stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  if (diag_unit == true) {

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);

  } else {

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);

  }

  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  // Analysis
  stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                   CUSPARSE_OPERATION_NON_TRANSPOSE,
                                   this->get_nrow(), this->get_nnz(),
                                   this->L_mat_descr_,
                                   this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                   this->L_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <>
void GPUAcceleratorMatrixCSR<float>::LAnalyse(const bool diag_unit) {

  cusparseStatus_t stat_t;

  // L part
  stat_t = cusparseCreateMatDescr(&this->L_mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatType(this->L_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatIndexBase(this->L_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatFillMode(this->L_mat_descr_, CUSPARSE_FILL_MODE_LOWER);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  if (diag_unit == true) {

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);

  } else {

    stat_t = cusparseSetMatDiagType(this->L_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);

  }

  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 

  stat_t = cusparseCreateSolveAnalysisInfo(&this->L_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  // Analysis
  stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                   CUSPARSE_OPERATION_NON_TRANSPOSE,
                                   this->get_nrow(), this->get_nnz(),
                                   this->L_mat_descr_,
                                   this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                   this->L_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <>
void GPUAcceleratorMatrixCSR<double>::UAnalyse(const bool diag_unit) {

  cusparseStatus_t stat_t;

  // U upart
  stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_UPPER);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  if (diag_unit == true) {

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);

  } else {

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);

  }

  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  // Analysis
  stat_t = cusparseDcsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                   CUSPARSE_OPERATION_NON_TRANSPOSE,
                                   this->get_nrow(), this->get_nnz(),
                                   this->U_mat_descr_,
                                   this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                   this->U_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <>
void GPUAcceleratorMatrixCSR<float>::UAnalyse(const bool diag_unit) {

  cusparseStatus_t stat_t;

  // U part
  stat_t = cusparseCreateMatDescr(&this->U_mat_descr_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatType(this->U_mat_descr_,CUSPARSE_MATRIX_TYPE_GENERAL);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatIndexBase(this->U_mat_descr_,CUSPARSE_INDEX_BASE_ZERO);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseSetMatFillMode(this->U_mat_descr_, CUSPARSE_FILL_MODE_UPPER);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  if (diag_unit == true) {

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_UNIT);

  } else {

    stat_t = cusparseSetMatDiagType(this->U_mat_descr_, CUSPARSE_DIAG_TYPE_NON_UNIT);

  }

  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseCreateSolveAnalysisInfo(&this->U_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  // Analysis
  stat_t = cusparseScsrsv_analysis(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                   CUSPARSE_OPERATION_NON_TRANSPOSE,
                                   this->get_nrow(), this->get_nnz(),
                                   this->U_mat_descr_,
                                   this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                   this->U_mat_info_);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::LAnalyseClear(void) {

  cusparseStatus_t stat_t;

  if (this->L_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->L_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->L_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->L_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  this->L_mat_descr_ = 0;
  this->L_mat_info_ = 0;

}

template <typename ValueType>
void GPUAcceleratorMatrixCSR<ValueType>::UAnalyseClear(void) {

  cusparseStatus_t stat_t;

  if (this->U_mat_info_ != 0) {
    stat_t = cusparseDestroySolveAnalysisInfo(this->U_mat_info_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  if (this->U_mat_descr_ != 0) {
    stat_t = cusparseDestroyMatDescr(this->U_mat_descr_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__); 
  }

  this->U_mat_descr_ = 0;
  this->U_mat_info_ = 0;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::LSolve(const BaseVector<double> &in, BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in);
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    double one = double(1.0);

    // Solve L
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::LSolve(const BaseVector<float> &in, BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in);
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    float one = float(1.0);

    // Solve L
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->L_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->L_mat_info_,
                                  cast_in->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::USolve(const BaseVector<double> &in, BaseVector<double> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow()); 

    const GPUAcceleratorVector<double> *cast_in = dynamic_cast<const GPUAcceleratorVector<double>*> (&in);
    GPUAcceleratorVector<double> *cast_out      = dynamic_cast<      GPUAcceleratorVector<double>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    double one = double(1.0);

    // Solve U
    stat_t = cusparseDcsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  cast_in->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::USolve(const BaseVector<float> &in, BaseVector<float> *out) const {

  if (this->get_nnz() > 0) {

    assert(this->L_mat_descr_ != 0);
    assert(this->U_mat_descr_ != 0);
    assert(this->L_mat_info_  != 0);
    assert(this->U_mat_info_  != 0);

    assert(in.  get_size()  >= 0);
    assert(out->get_size()  >= 0);
    assert(in.  get_size()  == this->get_ncol());
    assert(out->get_size()  == this->get_nrow());
    assert(this->get_ncol() == this->get_nrow());

    const GPUAcceleratorVector<float> *cast_in = dynamic_cast<const GPUAcceleratorVector<float>*> (&in);
    GPUAcceleratorVector<float> *cast_out      = dynamic_cast<      GPUAcceleratorVector<float>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    cusparseStatus_t stat_t;

    float one = float(1.0);

    // Solve U
    stat_t = cusparseScsrsv_solve(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_OPERATION_NON_TRANSPOSE,
                                  this->get_nrow(),
                                  &one,
                                  this->U_mat_descr_,
                                  this->mat_.val, this->mat_.row_offset, this->mat_.col,
                                  this->U_mat_info_,
                                  cast_in->vec_,
                                  cast_out->vec_);
    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractDiagonal(BaseVector<ValueType> *vec_diag) const {

  if (this->get_nnz() > 0)  {

    assert(vec_diag != NULL);
    assert(vec_diag->get_size() == this->get_nrow());

    GPUAcceleratorVector<ValueType> *cast_vec_diag  = dynamic_cast<GPUAcceleratorVector<ValueType>*> (vec_diag);

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_extract_diag<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                       cast_vec_diag->vec_);
    
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractInverseDiagonal(BaseVector<ValueType> *vec_inv_diag) const {

  if (this->get_nnz() > 0) {

    assert(vec_inv_diag != NULL);
    assert(vec_inv_diag->get_size() == this->get_nrow());

    GPUAcceleratorVector<ValueType> *cast_vec_inv_diag  = dynamic_cast<GPUAcceleratorVector<ValueType>*> (vec_inv_diag);

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_extract_inv_diag<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                           this->mat_.val, cast_vec_inv_diag->vec_);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractSubMatrix(const int row_offset,
                                                          const int col_offset,
                                                          const int row_size,
                                                          const int col_size,
                                                          BaseMatrix<ValueType> *mat) const {
  assert(mat != NULL);

  assert(row_offset >= 0);
  assert(col_offset >= 0);

  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);

  GPUAcceleratorMatrixCSR<ValueType> *cast_mat  = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (mat) ; 
  assert(cast_mat != NULL);

  int mat_nnz = 0;

  int *row_nnz = NULL;  
  //int *red_row_nnz  (int *) malloc(sizeof(int)*(row_size+1));
  int *sub_nnz = NULL;
  allocate_gpu<int>(row_size+1, &sub_nnz);
  allocate_gpu(row_size+1, &row_nnz);

  // compute the nnz per row in the new matrix

  dim3 BlockSize(this->local_backend_.GPU_block_size);
  dim3 GridSize(row_size / this->local_backend_.GPU_block_size + 1);
  
  kernel_csr_extract_submatrix_row_nnz<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                                  row_offset, col_offset, 
                                                                                  row_size, col_size, 
                                                                                  row_nnz);
    
  CHECK_CUDA_ERROR(__FILE__, __LINE__);      

  // compute the new nnz by reduction 
  
  
  // CPU reduction
  /*
  cudaMemcpy(red_row_nnz, // dst
             row_nnz,  // src
             (row_size+1)*sizeof(int), // size
             cudaMemcpyDeviceToHost);

  int sum=0;
  for (int i=0; i<row_size; ++i) {
    int tmp = red_row_nnz[i];
    red_row_nnz[i] = sum;
    sum += tmp;
  }

  mat_nnz = red_row_nnz[row_size] = sum ;
  */

  //TODO
  //move in extra file
  cum_sum<int, 256>(sub_nnz, row_nnz, row_size);
  
  cudaMemcpy(&mat_nnz, &sub_nnz[row_size],
             sizeof(int), cudaMemcpyDeviceToHost);

  // not empty submatrix
  if (mat_nnz > 0) {

    cast_mat->AllocateCSR(mat_nnz, row_size, col_size);

    // part of the CPU reduction section
    /*
    cudaMemcpy(cast_mat->mat_.row_offset, // dst
               red_row_nnz,  // src
               (row_size+1)*sizeof(int), // size
               cudaMemcpyHostToDevice);
    */
    
    free_gpu<int>(&cast_mat->mat_.row_offset);
    cast_mat->mat_.row_offset = sub_nnz;
    // copying the sub matrix
    
    kernel_csr_extract_submatrix_copy<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset, this->mat_.col, this->mat_.val,
                                                                                 row_offset, col_offset, 
                                                                                 row_size, col_size,
                                                                                 cast_mat->mat_.row_offset, cast_mat->mat_.col, cast_mat->mat_.val);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);      

  }

  free_gpu(&row_nnz);

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractL(BaseMatrix<ValueType> *L) const {
  
  assert(L != NULL);
  
  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);
  
  GPUAcceleratorMatrixCSR<ValueType> *cast_L = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (L);
  
  assert(cast_L != NULL);
  
  cast_L->Clear();
  
  // compute nnz per row
  int nrow = this->get_nrow();
  
  allocate_gpu<int>(nrow+1, &cast_L->mat_.row_offset);
  
  dim3 BlockSize(this->local_backend_.GPU_block_size);
  dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
  
  
  kernel_csr_slower_nnz_per_row<int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                              this->mat_.col, cast_L->mat_.row_offset+1);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  // partial sum row_nnz to obtain row_offset vector
  // TODO currently performing partial sum on host
  int *h_buffer = NULL;
  allocate_host(nrow+1, &h_buffer);
  cudaMemcpy(h_buffer+1, // dst
             cast_L->mat_.row_offset+1, // src
             nrow*sizeof(int), // size
             cudaMemcpyDeviceToHost);
  
  h_buffer[0] = 0;
  for (int i=1; i<nrow+1; ++i)
    h_buffer[i] += h_buffer[i-1];
  
  int nnz_L = h_buffer[nrow];
  
  cudaMemcpy(cast_L->mat_.row_offset, // dst
             h_buffer, // src
             (nrow+1)*sizeof(int), // size
             cudaMemcpyHostToDevice);
  
  free_host(&h_buffer);
  // end TODO
  
  // allocate lower triangular part structure
  allocate_gpu<int>(nnz_L, &cast_L->mat_.col);
  allocate_gpu<ValueType>(nnz_L, &cast_L->mat_.val);
  
  // fill lower triangular part
  kernel_csr_extract_l_triangular<ValueType, int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                                            this->mat_.col, this->mat_.val,
                                                                            cast_L->mat_.row_offset,
                                                                            cast_L->mat_.col,
                                                                            cast_L->mat_.val);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  cast_L->nrow_ = this->get_nrow();
  cast_L->ncol_ = this->get_ncol();
  cast_L->nnz_ = nnz_L;
  
  return true;
  
}


template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractLDiagonal(BaseMatrix<ValueType> *L) const {

  assert(L != NULL);
  
  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);
  
  GPUAcceleratorMatrixCSR<ValueType> *cast_L = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (L);
  
  assert(cast_L != NULL);
  
  cast_L->Clear();
  
  // compute nnz per row
  int nrow = this->get_nrow();
  
  allocate_gpu<int>(nrow+1, &cast_L->mat_.row_offset);
  
  dim3 BlockSize(this->local_backend_.GPU_block_size);
  dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

  kernel_csr_lower_nnz_per_row<int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                              this->mat_.col, cast_L->mat_.row_offset+1);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);

  // partial sum row_nnz to obtain row_offset vector
  // TODO currently performing partial sum on host
  int *h_buffer = NULL;
  allocate_host(nrow+1, &h_buffer);
  cudaMemcpy(h_buffer+1, // dst
             cast_L->mat_.row_offset+1, // src
             nrow*sizeof(int), // size
             cudaMemcpyDeviceToHost);

  h_buffer[0] = 0;
  for (int i=1; i<nrow+1; ++i)
    h_buffer[i] += h_buffer[i-1];
  
  int nnz_L = h_buffer[nrow];

  cudaMemcpy(cast_L->mat_.row_offset, // dst
             h_buffer, // src
             (nrow+1)*sizeof(int), // size
             cudaMemcpyHostToDevice);
  
  free_host(&h_buffer);
  // end TODO
  
  // allocate lower triangular part structure
  allocate_gpu<int>(nnz_L, &cast_L->mat_.col);
  allocate_gpu<ValueType>(nnz_L, &cast_L->mat_.val);
  
  // fill lower triangular part
  kernel_csr_extract_l_triangular<ValueType, int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                                            this->mat_.col, this->mat_.val,
                                                                            cast_L->mat_.row_offset,
                                                                            cast_L->mat_.col,
                                                                            cast_L->mat_.val);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  cast_L->nrow_ = this->get_nrow();
  cast_L->ncol_ = this->get_ncol();
  cast_L->nnz_ = nnz_L;
  
  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractU(BaseMatrix<ValueType> *U) const {
  
  assert(U != NULL);
  
  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);
  
  GPUAcceleratorMatrixCSR<ValueType> *cast_U = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (U);
  
  assert(cast_U != NULL);
  
  cast_U->Clear();
  
  // compute nnz per row
  int nrow = this->get_nrow();
  
  allocate_gpu<int>(nrow+1, &cast_U->mat_.row_offset);
  
  dim3 BlockSize(this->local_backend_.GPU_block_size);
  dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
  
  
  kernel_csr_supper_nnz_per_row<int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                              this->mat_.col, cast_U->mat_.row_offset+1);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  // partial sum row_nnz to obtain row_offset vector
  // TODO currently performing partial sum on host
  int *h_buffer = NULL;
  allocate_host(nrow+1, &h_buffer);
  cudaMemcpy(h_buffer+1, // dst
             cast_U->mat_.row_offset+1, // src
             nrow*sizeof(int), // size
             cudaMemcpyDeviceToHost);
  
  h_buffer[0] = 0;
  for (int i=1; i<nrow+1; ++i)
    h_buffer[i] += h_buffer[i-1];
  
  int nnz_L = h_buffer[nrow];
  
  cudaMemcpy(cast_U->mat_.row_offset, // dst
             h_buffer, // src
             (nrow+1)*sizeof(int), // size
             cudaMemcpyHostToDevice);
  
  free_host(&h_buffer);
  // end TODO
  
  // allocate lower triangular part structure
  allocate_gpu<int>(nnz_L, &cast_U->mat_.col);
  allocate_gpu<ValueType>(nnz_L, &cast_U->mat_.val);
  
  // fill upper triangular part
  kernel_csr_extract_u_triangular<ValueType, int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                                            this->mat_.col, this->mat_.val,
                                                                            cast_U->mat_.row_offset,
                                                                            cast_U->mat_.col,
                                                                            cast_U->mat_.val);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  cast_U->nrow_ = this->get_nrow();
  cast_U->ncol_ = this->get_ncol();
  cast_U->nnz_ = nnz_L;
  
  return true;
  
}


template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractUDiagonal(BaseMatrix<ValueType> *U) const {

  assert(U != NULL);
  
  assert(this->get_nrow() > 0);
  assert(this->get_ncol() > 0);
  
  GPUAcceleratorMatrixCSR<ValueType> *cast_U = dynamic_cast<GPUAcceleratorMatrixCSR<ValueType>*> (U);
  
  assert(cast_U != NULL);
  
  cast_U->Clear();
  
  // compute nnz per row
  int nrow = this->get_nrow();
  
  allocate_gpu<int>(nrow+1, &cast_U->mat_.row_offset);
  
  dim3 BlockSize(this->local_backend_.GPU_block_size);
  dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);
  
  
  kernel_csr_upper_nnz_per_row<int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                              this->mat_.col, cast_U->mat_.row_offset+1);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  // partial sum row_nnz to obtain row_offset vector
  // TODO currently performing partial sum on host
  int *h_buffer = NULL;
  allocate_host(nrow+1, &h_buffer);
  cudaMemcpy(h_buffer+1, // dst
             cast_U->mat_.row_offset+1, // src
             nrow*sizeof(int), // size
             cudaMemcpyDeviceToHost);

  h_buffer[0] = 0;
  for (int i=1; i<nrow+1; ++i)
    h_buffer[i] += h_buffer[i-1];
  
  int nnz_L = h_buffer[nrow];

  cudaMemcpy(cast_U->mat_.row_offset, // dst
             h_buffer, // src
             (nrow+1)*sizeof(int), // size
             cudaMemcpyHostToDevice);
  
  free_host(&h_buffer);
  // end TODO
  
  // allocate lower triangular part structure
  allocate_gpu<int>(nnz_L, &cast_U->mat_.col);
  allocate_gpu<ValueType>(nnz_L, &cast_U->mat_.val);
  
  // fill lower triangular part
  kernel_csr_extract_u_triangular<ValueType, int> <<<GridSize, BlockSize>>>(nrow, this->mat_.row_offset,
                                                                            this->mat_.col, this->mat_.val,
                                                                            cast_U->mat_.row_offset,
                                                                            cast_U->mat_.col,
                                                                            cast_U->mat_.val);
  CHECK_CUDA_ERROR(__FILE__,__LINE__);
  
  cast_U->nrow_ = this->get_nrow();
  cast_U->ncol_ = this->get_ncol();
  cast_U->nnz_ = nnz_L;
  
  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::MaximalIndependentSet(int &size,
                                                               BaseVector<int> *permutation) const {
  assert(permutation != NULL);
  GPUAcceleratorVector<int> *cast_perm = dynamic_cast<GPUAcceleratorVector<int>*> (permutation);
  assert(cast_perm != NULL);
  assert(this->get_nrow() == this->get_ncol());

  int *h_row_offset = NULL;
  int *h_col = NULL;

  allocate_host(this->get_nrow()+1, &h_row_offset);
  allocate_host(this->get_nnz(), &h_col);

  cudaMemcpy(h_row_offset, this->mat_.row_offset, (this->get_nrow()+1)*sizeof(int), cudaMemcpyDeviceToHost);
  cudaMemcpy(h_col, this->mat_.col, this->get_nnz()*sizeof(int), cudaMemcpyDeviceToHost);

  int *mis = NULL;
  allocate_host(this->get_nrow(), &mis);
  memset(mis, 0, sizeof(int)*this->get_nrow());

  size = 0 ;

  for (int ai=0; ai<this->get_nrow(); ++ai) {

    if (mis[ai] == 0) {

      // set the node
      mis[ai] = 1;
      ++size ;

      //remove all nbh nodes (without diagonal)
      for (int aj=h_row_offset[ai]; aj<h_row_offset[ai+1]; ++aj)
        if (ai != h_col[aj])
          mis[h_col[aj]] = -1 ;
      
    }
  }

  int *h_perm = NULL;
  allocate_host(this->get_nrow(), &h_perm);

  int pos = 0;
  for (int ai=0; ai<this->get_nrow(); ++ai) {

    if (mis[ai] == 1) {

      h_perm[ai] = pos;
      ++pos;

    } else {

      h_perm[ai] = size + ai - pos;

    }

  }
  
  // Check the permutation
  //
  //  for (int ai=0; ai<this->get_nrow(); ++ai) {
  //    assert( h_perm[ai] >= 0 );
  //    assert( h_perm[ai] < this->get_nrow() );
  //  }


  cast_perm->Allocate(this->get_nrow());
  cudaMemcpy(cast_perm->vec_, h_perm, permutation->get_size()*sizeof(int), cudaMemcpyHostToDevice);

  free_host(&h_row_offset);
  free_host(&h_col);

  free_host(&h_perm);
  free_host(&mis);

  return true;
}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::MultiColoring(int &num_colors,
                                                       int **size_colors,
                                                       BaseVector<int> *permutation) const {

  assert(permutation != NULL);
  GPUAcceleratorVector<int> *cast_perm = dynamic_cast<GPUAcceleratorVector<int>*> (permutation);
  assert(cast_perm != NULL);

  // node colors (init value = 0 i.e. no color)
  int *color = NULL;
  int *h_row_offset = NULL;
  int *h_col = NULL;
  int size = this->get_nrow();
  allocate_host(size, &color);
  allocate_host(this->get_nrow()+1, &h_row_offset);
  allocate_host(this->get_nnz(), &h_col);

  cudaMemcpy(h_row_offset, this->mat_.row_offset, (this->get_nrow()+1)*sizeof(int), cudaMemcpyDeviceToHost);
  cudaMemcpy(h_col, this->mat_.col, this->get_nnz()*sizeof(int), cudaMemcpyDeviceToHost);

  memset(color, 0, size*sizeof(int));
  num_colors = 0;
  std::vector<bool> row_col;

  for (int ai=0; ai<this->get_nrow(); ++ai) {
    color[ai] = 1;
    row_col.clear();
    row_col.assign(num_colors+2, false);

    for (int aj=h_row_offset[ai]; aj<h_row_offset[ai+1]; ++aj)
      if (ai != h_col[aj])
        row_col[color[h_col[aj]]] = true;

    for (int aj=h_row_offset[ai]; aj<h_row_offset[ai+1]; ++aj)
      if (row_col[color[ai]] == true)
        ++color[ai];

    if (color[ai] > num_colors)
      num_colors = color[ai];

  }

  free_host(&h_row_offset);
  free_host(&h_col);

  allocate_host(num_colors, size_colors);
  set_to_zero_host(num_colors, *size_colors);

  int *offsets_color = NULL;
  allocate_host(num_colors, &offsets_color);
  memset(offsets_color, 0, sizeof(int)*num_colors);

  for (int i=0; i<this->get_nrow(); ++i) 
    ++(*size_colors)[color[i]-1];

  int total=0;
  for (int i=1; i<num_colors; ++i) {

    total += (*size_colors)[i-1];
    offsets_color[i] = total; 
    //   LOG_INFO("offsets = " << total);

  }

  int *h_perm = NULL;
  allocate_host(this->get_nrow(), &h_perm);

  for (int i=0; i<this->get_nrow(); ++i) {

    h_perm[i] = offsets_color[ color[i]-1 ] ;
    ++offsets_color[color[i]-1];

  }

  cast_perm->Allocate(this->get_nrow());
  cudaMemcpy(cast_perm->vec_, h_perm, permutation->get_size()*sizeof(int), cudaMemcpyHostToDevice);

  free_host(&h_perm);
  free_host(&color);
  free_host(&offsets_color);

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::Scale(const double alpha) {

  if (this->get_nnz() > 0) {

    cublasStatus_t stat_t;

    stat_t = cublasDscal(CUBLAS_HANDLE(this->local_backend_.GPU_cublas_handle),
                         this->get_nnz(), &alpha,
                         this->mat_.val, 1);
    CHECK_CUBLAS_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::Scale(const float alpha) {

  if (this->get_nnz() > 0) {

    cublasStatus_t stat_t;

    stat_t = cublasSscal(CUBLAS_HANDLE(this->local_backend_.GPU_cublas_handle),
                         this->get_nnz(), &alpha,
                         this->mat_.val, 1);
    CHECK_CUBLAS_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ScaleDiagonal(const ValueType alpha) {

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_scale_diagonal<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                         alpha, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ScaleOffDiagonal(const ValueType alpha) {

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_scale_offdiagonal<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                            alpha, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::AddScalarDiagonal(const ValueType alpha) {

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_add_diagonal<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                       alpha, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::AddScalarOffDiagonal(const ValueType alpha) {

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_add_offdiagonal<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                       alpha, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::AddScalar(const ValueType alpha) {

  if (this->get_nnz() > 0) {

    int nnz = this->get_nnz();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nnz / this->local_backend_.GPU_block_size + 1);

    kernel_buffer_addscalar<ValueType, int> <<<GridSize, BlockSize>>> (nnz, alpha, this->mat_.val);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::DiagonalMatrixMultR(const BaseVector<ValueType> &diag) {

  assert(diag.get_size() == this->get_ncol());

  const GPUAcceleratorVector<ValueType> *cast_diag = dynamic_cast<const GPUAcceleratorVector<ValueType>*> (&diag);
  assert(cast_diag!= NULL);

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_diagmatmult_r<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset, this->mat_.col,
                                                                      cast_diag->vec_, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::DiagonalMatrixMultL(const BaseVector<ValueType> &diag) {

  assert(diag.get_size() == this->get_ncol());

  const GPUAcceleratorVector<ValueType> *cast_diag = dynamic_cast<const GPUAcceleratorVector<ValueType>*> (&diag);
  assert(cast_diag!= NULL);

  if (this->get_nnz() > 0) {

    int nrow = this->get_nrow();
    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_diagmatmult_l<ValueType, int> <<<GridSize, BlockSize>>> (nrow, this->mat_.row_offset,
                                                                      cast_diag->vec_, this->mat_.val);

    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::MatMatMult(const BaseMatrix<ValueType> &A, const BaseMatrix<ValueType> &B) {

  assert(A.get_ncol() == B.get_nrow());
  assert(A.get_nrow() > 0);
  assert(B.get_ncol() > 0);
  assert(B.get_nrow() > 0);

  const GPUAcceleratorMatrixCSR<ValueType> *cast_mat_A = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&A);
  const GPUAcceleratorMatrixCSR<ValueType> *cast_mat_B = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&B);
  assert(cast_mat_A != NULL);
  assert(cast_mat_B != NULL);

  this->Clear();

  int m = cast_mat_A->get_nrow();
  int n = cast_mat_B->get_ncol();
  int k = cast_mat_B->get_nrow();
  int nnzC = 0;

  allocate_gpu(m+1, &this->mat_.row_offset);
  CHECK_CUDA_ERROR(__FILE__, __LINE__);

  cusparseStatus_t stat_t;

  stat_t = cusparseSetPointerMode(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                  CUSPARSE_POINTER_MODE_HOST);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  stat_t = cusparseXcsrgemmNnz(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                               CUSPARSE_OPERATION_NON_TRANSPOSE,
                               CUSPARSE_OPERATION_NON_TRANSPOSE,
                               m, n, k,
                               cast_mat_A->mat_descr_, cast_mat_A->get_nnz(),
                               cast_mat_A->mat_.row_offset, cast_mat_A->mat_.col,
                               cast_mat_B->mat_descr_, cast_mat_B->get_nnz(),
                               cast_mat_B->mat_.row_offset, cast_mat_B->mat_.col,
                               this->mat_descr_, this->mat_.row_offset,
                               &nnzC);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  allocate_gpu(nnzC, &this->mat_.col);
  CHECK_CUDA_ERROR(__FILE__, __LINE__);

  allocate_gpu(nnzC, &this->mat_.val);
  CHECK_CUDA_ERROR(__FILE__, __LINE__);

  this->nrow_ = m;
  this->ncol_ = n;
  this->nnz_  = nnzC;

  stat_t = __cusparseXcsrgemm__(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                CUSPARSE_OPERATION_NON_TRANSPOSE,
                                CUSPARSE_OPERATION_NON_TRANSPOSE,
                                m, n, k,
                                // A
                                cast_mat_A->mat_descr_, cast_mat_A->get_nnz(),
                                cast_mat_A->mat_.val,
                                cast_mat_A->mat_.row_offset, cast_mat_A->mat_.col,
                                // B
                                cast_mat_B->mat_descr_, cast_mat_B->get_nnz(),
                                cast_mat_B->mat_.val,
                                cast_mat_B->mat_.row_offset, cast_mat_B->mat_.col,
                                // C
                                this->mat_descr_,
                                this->mat_.val,
                                this->mat_.row_offset, this->mat_.col);
  CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::Gershgorin(ValueType &lambda_min,
                                                    ValueType &lambda_max) const {
  return false;
}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::MatrixAdd(const BaseMatrix<ValueType> &mat, const ValueType alpha,
                                                   const ValueType beta, const bool structure) {

  if (this->get_nnz() > 0) {

    const GPUAcceleratorMatrixCSR<ValueType> *cast_mat = dynamic_cast<const GPUAcceleratorMatrixCSR<ValueType>*> (&mat);
    assert(cast_mat != NULL);

    assert(cast_mat->get_nrow() == this->get_nrow());
    assert(cast_mat->get_ncol() == this->get_ncol());
    assert(this    ->get_nnz() > 0);  
    assert(cast_mat->get_nnz() > 0);

    if (structure == false) {

      int nrow = this->get_nrow();
      dim3 BlockSize(this->local_backend_.GPU_block_size);
      dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

      kernel_csr_add_csr_same_struct<ValueType, int> <<<GridSize, BlockSize>>> (nrow,
                                                                                this->mat_.row_offset, this->mat_.col,
                                                                                cast_mat->mat_.row_offset,
                                                                                cast_mat->mat_.col, cast_mat->mat_.val,
                                                                                alpha, beta, this->mat_.val);

      CHECK_CUDA_ERROR(__FILE__, __LINE__);

    } else {
      // New structure with CUSPARSE routines

      int m = this->get_nrow();
      int n = this->get_ncol();
      int *csrRowPtrC = NULL;
      int *csrColC = NULL;
      ValueType *csrValC = NULL;
      int nnzC;

      allocate_gpu(m+1, &csrRowPtrC);

      cusparseStatus_t stat_t;

      cusparseMatDescr_t desc_mat_C = 0;

      stat_t = cusparseCreateMatDescr(&desc_mat_C);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      stat_t = cusparseSetMatIndexBase(desc_mat_C, CUSPARSE_INDEX_BASE_ZERO);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      stat_t = cusparseSetMatType(desc_mat_C, CUSPARSE_MATRIX_TYPE_GENERAL);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      stat_t = cusparseSetPointerMode(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                      CUSPARSE_POINTER_MODE_HOST);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      stat_t = cusparseXcsrgeamNnz(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                   m, n,
                                   this->mat_descr_, this->get_nnz(),
                                   this->mat_.row_offset, this->mat_.col,
                                   cast_mat->mat_descr_, cast_mat->get_nnz(),
                                   cast_mat->mat_.row_offset, cast_mat->mat_.col,
                                   desc_mat_C, csrRowPtrC,
                                   &nnzC);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      allocate_gpu(nnzC, &csrColC);
      allocate_gpu(nnzC, &csrValC);

      stat_t = __cusparseXcsrgeam__(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                                    m, n,
                                    // A
                                    &alpha,
                                    this->mat_descr_, this->get_nnz(),
                                    this->mat_.val,
                                    this->mat_.row_offset, this->mat_.col,
                                    // B
                                    &beta,
                                    cast_mat->mat_descr_, cast_mat->get_nnz(),
                                    cast_mat->mat_.val,
                                    cast_mat->mat_.row_offset, cast_mat->mat_.col,
                                    // C
                                    desc_mat_C,
                                    csrValC,
                                    csrRowPtrC, csrColC);

      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      stat_t = cusparseDestroyMatDescr(desc_mat_C);
      CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

      this->Clear();

      this->mat_.row_offset = csrRowPtrC;
      this->mat_.col = csrColC;
      this->mat_.val = csrValC;

      this->nrow_ = m;
      this->ncol_ = n;
      this->nnz_  = nnzC;

    }

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::Compress(const double drop_off) {

  if (this->get_nnz() > 0) {

    GPUAcceleratorMatrixCSR<ValueType> tmp(this->local_backend_);

    tmp.CopyFrom(*this);

    int mat_nnz = 0;

    int *row_offset = NULL;
    allocate_gpu(this->get_nrow()+1, &row_offset);

    int *mat_row_offset = NULL;
    allocate_gpu(this->get_nrow()+1, &mat_row_offset);
    
    set_to_zero_gpu(this->local_backend_.GPU_block_size, 
                    this->local_backend_.GPU_max_threads,
                    this->get_nrow()+1, row_offset); 


    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(this->get_nrow() / this->local_backend_.GPU_block_size + 1);
    
    kernel_csr_compress_count_nrow<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset,
                                                                              this->mat_.col,
                                                                              this->mat_.val,
                                                                              this->get_nrow(),
                                                                              drop_off,
                                                                              row_offset);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);      

    // TODO
    cum_sum<int, 256>(mat_row_offset, row_offset, this->get_nrow());
  
    // get the new mat nnz
    cudaMemcpy(&mat_nnz, &mat_row_offset[this->get_nrow()],
               sizeof(int), cudaMemcpyDeviceToHost);
    
    this->AllocateCSR(mat_nnz, this->get_nrow(), this->get_ncol());

    // TODO - just exchange memory pointers
    // copy row_offset
    cudaMemcpy(this->mat_.row_offset, mat_row_offset,
               (this->get_nrow()+1)*sizeof(int), cudaMemcpyDeviceToDevice);
    
    
    // copy col and val

    kernel_csr_compress_copy<ValueType, int> <<<GridSize, BlockSize>>> (tmp.mat_.row_offset,
                                                                        tmp.mat_.col,
                                                                        tmp.mat_.val,
                                                                        tmp.get_nrow(),
                                                                        drop_off,
                                                                        this->mat_.row_offset,
                                                                        this->mat_.col,
                                                                        this->mat_.val);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);      


    free_gpu(&row_offset);
    free_gpu(&mat_row_offset);
        
    
  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<double>::Transpose(void) {

  if (this->get_nnz() > 0) {

    GPUAcceleratorMatrixCSR<double> tmp(this->local_backend_);

    tmp.CopyFrom(*this);

    this->Clear();
    this->AllocateCSR(tmp.get_nnz(), tmp.get_ncol(), tmp.get_nrow());

    cusparseStatus_t stat_t;

    stat_t = cusparseDcsr2csc(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                              tmp.get_nrow(), tmp.get_ncol(), tmp.get_nnz(),
                              tmp.mat_.val, tmp.mat_.row_offset, tmp.mat_.col,
                              this->mat_.val, this->mat_.col, this->mat_.row_offset,
                              CUSPARSE_ACTION_NUMERIC,
                              CUSPARSE_INDEX_BASE_ZERO);

    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <>
bool GPUAcceleratorMatrixCSR<float>::Transpose(void) {

  if (this->get_nnz() > 0) {

    GPUAcceleratorMatrixCSR<float> tmp(this->local_backend_);

    tmp.CopyFrom(*this);

    this->Clear();
    this->AllocateCSR(tmp.get_nnz(), tmp.get_ncol(), tmp.get_nrow());

    cusparseStatus_t stat_t;

    stat_t = cusparseScsr2csc(CUSPARSE_HANDLE(this->local_backend_.GPU_cusparse_handle),
                              tmp.get_nrow(), tmp.get_ncol(), tmp.get_nnz(),
                              tmp.mat_.val, tmp.mat_.row_offset, tmp.mat_.col,
                              this->mat_.val, this->mat_.col, this->mat_.row_offset,
                              CUSPARSE_ACTION_NUMERIC,
                              CUSPARSE_INDEX_BASE_ZERO);

    CHECK_CUSPARSE_ERROR(stat_t, __FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ReplaceColumnVector(const int idx, const BaseVector<ValueType> &vec) {

  assert(&vec != NULL);
  assert(vec.get_size() == this->nrow_);

  if (this->get_nnz() > 0) {

    const GPUAcceleratorVector<ValueType> *cast_vec = dynamic_cast<const GPUAcceleratorVector<ValueType>*> (&vec);
    assert(cast_vec != NULL);

    int *row_offset = NULL;
    int *col = NULL;
    ValueType *val = NULL;

    int nrow = this->get_nrow();
    int ncol = this->get_ncol();

    allocate_gpu(nrow+1, &row_offset);

    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(nrow / this->local_backend_.GPU_block_size + 1);

    kernel_csr_replace_column_vector_offset<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset,
                                                                                       this->mat_.col,
                                                                                       nrow,
                                                                                       idx,
                                                                                       cast_vec->vec_,
                                                                                       row_offset);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    int *host_offset = NULL;
    allocate_host(nrow+1, &host_offset);

    cudaMemcpy(host_offset,
               row_offset,
               sizeof(int)*(nrow+1),
               cudaMemcpyDeviceToHost);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    host_offset[0] = 0;
    for (int i=0; i<nrow; ++i)
      host_offset[i+1] += host_offset[i];

    int nnz  = host_offset[nrow];

    cudaMemcpy(row_offset,
               host_offset,
               sizeof(int)*(nrow+1),
               cudaMemcpyHostToDevice);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    allocate_gpu(nnz, &col);
    allocate_gpu(nnz, &val);

    kernel_csr_replace_column_vector<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset,
                                                                                this->mat_.col,
                                                                                this->mat_.val,
                                                                                nrow,
                                                                                idx,
                                                                                cast_vec->vec_,
                                                                                row_offset,
                                                                                col,
                                                                                val);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    this->Clear();
    this->SetDataPtrCSR(&row_offset, &col, &val, nnz, nrow, ncol);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractColumnVector(const int idx, BaseVector<ValueType> *vec) const {

  assert(vec != NULL);
  assert(vec->get_size() == this->nrow_);

  if (this->get_nnz() > 0) {

    GPUAcceleratorVector<ValueType> *cast_vec = dynamic_cast<GPUAcceleratorVector<ValueType>*> (vec);
    assert(cast_vec != NULL);

    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(this->get_nrow() / this->local_backend_.GPU_block_size + 1);

    kernel_csr_extract_column_vector<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset,
                                                                                this->mat_.col,
                                                                                this->mat_.val,
                                                                                this->get_nrow(),
                                                                                idx,
                                                                                cast_vec->vec_);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}

template <typename ValueType>
bool GPUAcceleratorMatrixCSR<ValueType>::ExtractRowVector(const int idx, BaseVector<ValueType> *vec) const {

  assert(vec != NULL);
  assert(vec->get_size() == this->ncol_);

  if (this->get_nnz() > 0) {

    GPUAcceleratorVector<ValueType> *cast_vec = dynamic_cast<GPUAcceleratorVector<ValueType>*> (vec);
    assert(cast_vec != NULL);

    cast_vec->Zeros();

    // Get nnz of row idx
    int nnz[2];

    cudaMemcpy(nnz,
               this->mat_.row_offset+idx,
               2*sizeof(int),
               cudaMemcpyDeviceToHost);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

    int row_nnz = nnz[1] - nnz[0];

    dim3 BlockSize(this->local_backend_.GPU_block_size);
    dim3 GridSize(row_nnz / this->local_backend_.GPU_block_size + 1);

    kernel_csr_extract_row_vector<ValueType, int> <<<GridSize, BlockSize>>> (this->mat_.row_offset,
                                                                             this->mat_.col,
                                                                             this->mat_.val,
                                                                             row_nnz,
                                                                             idx,
                                                                             cast_vec->vec_);
    CHECK_CUDA_ERROR(__FILE__, __LINE__);

  }

  return true;

}


template class GPUAcceleratorMatrixCSR<double>;
template class GPUAcceleratorMatrixCSR<float>;

}
