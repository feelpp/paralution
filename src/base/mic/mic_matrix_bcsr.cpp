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
#include "mic_matrix_csr.hpp"
#include "mic_matrix_coo.hpp"
#include "mic_matrix_dia.hpp"
#include "mic_matrix_ell.hpp"
#include "mic_matrix_hyb.hpp"
#include "mic_matrix_mcsr.hpp"
#include "mic_matrix_bcsr.hpp"
#include "mic_matrix_dense.hpp"
#include "mic_vector.hpp"
#include "../host/host_matrix_bcsr.hpp"
#include "../base_matrix.hpp"
#include "../base_vector.hpp"
#include "../backend_manager.hpp"
#include "../../utils/log.hpp"
#include "mic_utils.hpp"
#include "mic_allocate_free.hpp"
#include "../matrix_formats_ind.hpp"



namespace paralution {

template <typename ValueType>
MICAcceleratorMatrixBCSR<ValueType>::MICAcceleratorMatrixBCSR() {

  // no default constructors
  LOG_INFO("no default constructor");
  FATAL_ERROR(__FILE__, __LINE__);

}

template <typename ValueType>
MICAcceleratorMatrixBCSR<ValueType>::MICAcceleratorMatrixBCSR(const Paralution_Backend_Descriptor local_backend) {

  LOG_DEBUG(this, "MICAcceleratorMatrixBCSR::MICAcceleratorMatrixBCSR()",
            "constructor with local_backend");

  this->set_backend(local_backend); 

  // this is not working anyway...
  FATAL_ERROR(__FILE__, __LINE__);
}


template <typename ValueType>
MICAcceleratorMatrixBCSR<ValueType>::~MICAcceleratorMatrixBCSR() {

  LOG_DEBUG(this, "MICAcceleratorMatrixBCSR::~MICAcceleratorMatrixBCSR()",
            "destructor");

  this->Clear();

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::info(void) const {

  LOG_INFO("MICAcceleratorMatrixBCSR<ValueType>");

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::AllocateBCSR(const int nnz, const int nrow, const int ncol) {

  assert(nnz >= 0);
  assert(ncol >= 0);
  assert(nrow >= 0);

  if (this->get_nnz() > 0)
    this->Clear();

  if (nnz > 0) {

    FATAL_ERROR(__FILE__, __LINE__);
   

  }

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::Clear() {

  if (this->get_nnz() > 0) {

    FATAL_ERROR(__FILE__, __LINE__);


  }


}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::CopyFromHost(const HostMatrix<ValueType> &src) {

  const HostMatrixBCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // CPU to MIC copy
  if ((cast_mat = dynamic_cast<const HostMatrixBCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateBCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );

    assert((this->get_nnz()  == src.get_nnz())  &&
	   (this->get_nrow() == src.get_nrow()) &&
	   (this->get_ncol() == src.get_ncol()) );

    cast_mat->get_nnz();

    FATAL_ERROR(__FILE__, __LINE__);    
    
  } else {
    
    LOG_INFO("Error unsupported MIC matrix type");
    this->info();
    src.info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::CopyToHost(HostMatrix<ValueType> *dst) const {

  HostMatrixBCSR<ValueType> *cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // MIC to CPU copy
  if ((cast_mat = dynamic_cast<HostMatrixBCSR<ValueType>*> (dst)) != NULL) {

    cast_mat->set_backend(this->local_backend_);   

  if (dst->get_nnz() == 0)
    cast_mat->AllocateBCSR(this->get_nnz(), this->get_nrow(), this->get_ncol() );

    assert((this->get_nnz()  == dst->get_nnz())  &&
	   (this->get_nrow() == dst->get_nrow()) &&
	   (this->get_ncol() == dst->get_ncol()) );

    FATAL_ERROR(__FILE__, __LINE__);    
   
    
  } else {
    
    LOG_INFO("Error unsupported MIC matrix type");
    this->info();
    dst->info();
    FATAL_ERROR(__FILE__, __LINE__);
    
  }

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::CopyFrom(const BaseMatrix<ValueType> &src) {

  const MICAcceleratorMatrixBCSR<ValueType> *mic_cast_mat;
  const HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == src.get_mat_format());

  // MIC to MIC copy
  if ((mic_cast_mat = dynamic_cast<const MICAcceleratorMatrixBCSR<ValueType>*> (&src)) != NULL) {
    
  if (this->get_nnz() == 0)
    this->AllocateBCSR(src.get_nnz(), src.get_nrow(), src.get_ncol() );  

    assert((this->get_nnz()  == src.get_nnz())  &&
	   (this->get_nrow() == src.get_nrow()) &&
	   (this->get_ncol() == src.get_ncol()) );

    mic_cast_mat->get_nnz();

    FATAL_ERROR(__FILE__, __LINE__);    

    
  } else {

    //CPU to MIC
    if ((host_cast_mat = dynamic_cast<const HostMatrix<ValueType>*> (&src)) != NULL) {
      
      this->CopyFromHost(*host_cast_mat);
      
    } else {
      
      LOG_INFO("Error unsupported MIC matrix type");
      this->info();
      src.info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }
    
  }

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::CopyTo(BaseMatrix<ValueType> *dst) const {

  MICAcceleratorMatrixBCSR<ValueType> *mic_cast_mat;
  HostMatrix<ValueType> *host_cast_mat;

  // copy only in the same format
  assert(this->get_mat_format() == dst->get_mat_format());

  // MIC to MIC copy
  if ((mic_cast_mat = dynamic_cast<MICAcceleratorMatrixBCSR<ValueType>*> (dst)) != NULL) {

    mic_cast_mat->set_backend(this->local_backend_);       

  if (this->get_nnz() == 0)
    mic_cast_mat->AllocateBCSR(dst->get_nnz(), dst->get_nrow(), dst->get_ncol() );

    assert((this->get_nnz()  == dst->get_nnz())  &&
	   (this->get_nrow() == dst->get_nrow()) &&
	   (this->get_ncol() == dst->get_ncol()) );

    FATAL_ERROR(__FILE__, __LINE__);    
    
  } else {

    //MIC to CPU
    if ((host_cast_mat = dynamic_cast<HostMatrix<ValueType>*> (dst)) != NULL) {
      
      this->CopyToHost(host_cast_mat);

    } else {
      
      LOG_INFO("Error unsupported MIC matrix type");
      this->info();
      dst->info();
      FATAL_ERROR(__FILE__, __LINE__);
      
    }

  }


}


template <typename ValueType>
bool MICAcceleratorMatrixBCSR<ValueType>::ConvertFrom(const BaseMatrix<ValueType> &mat) {

  this->Clear();

  // empty matrix is empty matrix
  if (mat.get_nnz() == 0)
    return true;


  const MICAcceleratorMatrixBCSR<ValueType>   *cast_mat_bcsr;
  if ((cast_mat_bcsr = dynamic_cast<const MICAcceleratorMatrixBCSR<ValueType>*> (&mat)) != NULL) {

      this->CopyFrom(*cast_mat_bcsr);
      return true;

  }

  /*
  const MICAcceleratorMatrixCSR<ValueType>   *cast_mat_csr;
  if ((cast_mat_csr = dynamic_cast<const MICAcceleratorMatrixCSR<ValueType>*> (&mat)) != NULL) {
    
    this->Clear();
    
    FATAL_ERROR(__FILE__, __LINE__);
    
    this->nrow_ = cast_mat_csr->get_nrow();
    this->ncol_ = cast_mat_csr->get_ncol();
    this->nnz_  = cast_mat_csr->get_nnz();
    
    return true;

  }
  */


  return false;

}

template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::Apply(const BaseVector<ValueType> &in, BaseVector<ValueType> *out) const {
/*
  assert(in.  get_size() >= 0);
  assert(out->get_size() >= 0);
  assert(in.  get_size() == this->get_ncol());
  assert(out->get_size() == this->get_nrow());


  const MICAcceleratorVector<ValueType> *cast_in = dynamic_cast<const MICAcceleratorVector<ValueType>*> (&in) ; 
  MICAcceleratorVector<ValueType> *cast_out      = dynamic_cast<      MICAcceleratorVector<ValueType>*> (out) ; 

  assert(cast_in != NULL);
  assert(cast_out!= NULL);
*/
  FATAL_ERROR(__FILE__, __LINE__);    

}


template <typename ValueType>
void MICAcceleratorMatrixBCSR<ValueType>::ApplyAdd(const BaseVector<ValueType> &in, const ValueType scalar,
                                                  BaseVector<ValueType> *out) const {
  FATAL_ERROR(__FILE__, __LINE__);
}


template class MICAcceleratorMatrixBCSR<double>;
template class MICAcceleratorMatrixBCSR<float>;

}
