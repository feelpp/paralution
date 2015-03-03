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
#include "host_matrix_mcsr.hpp"
#include "host_matrix_csr.hpp"
#include "host_conversion.hpp"
#include "host_vector.hpp"
#include "../../utils/log.hpp"
#include "../../utils/allocate_free.hpp"
#include "../matrix_formats_ind.hpp"

#include <complex>

#ifdef _OPENMP
#include <omp.h>
#else
#define omp_set_num_threads(num);
#endif

namespace paralution {

template <typename ValueType>
HostMatrixMCSR<ValueType>::HostMatrixMCSR() {

  // no default constructors
  LOG_INFO("no default constructor");
  FATAL_ERROR(__FILE__, __LINE__);

}

template <typename ValueType>
HostMatrixMCSR<ValueType>::HostMatrixMCSR(const Paralution_Backend_Descriptor local_backend) {

  LOG_DEBUG(this, "HostMatrixMCSR::HostMatrixMCSR()",
            "constructor with local_backend");

  this->mat_.row_offset = NULL;
  this->mat_.val = NULL;
  this->mat_.col = NULL;

  this->set_backend(local_backend);

}

template <typename ValueType>
HostMatrixMCSR<ValueType>::~HostMatrixMCSR() {

  LOG_DEBUG(this, "HostMatrixMCSR::~HostMatrixMCSR()",
            "destructor");

  this->Clear();

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::info(void) const {

  LOG_INFO("HostMatrixMCSR<ValueType>");

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::Clear() {

  if (this->nnz_ > 0) {

    free_host(&this->mat_.row_offset);
    free_host(&this->mat_.col);
    free_host(&this->mat_.val);

    this->nrow_ = 0;
    this->ncol_ = 0;
    this->nnz_  = 0;

  }

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::AllocateMCSR(const int nnz, const int nrow, const int ncol) {

  assert( nnz   >= 0);
  assert( ncol  >= 0);
  assert( nrow  >= 0);

  if (this->nnz_ > 0)
    this->Clear();

  if (nnz > 0) {

    allocate_host(nrow+1, &this->mat_.row_offset);
    allocate_host(nnz,    &this->mat_.col);
    allocate_host(nnz,    &this->mat_.val);

    set_to_zero_host(nrow+1, mat_.row_offset);
    set_to_zero_host(nnz, mat_.col);
    set_to_zero_host(nnz, mat_.val);

    this->nrow_ = nrow;
    this->ncol_ = ncol;
    this->nnz_  = nnz;

  }

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::CopyFrom(const BaseMatrix<ValueType> &mat) {

  // copy only in the same format
  assert(this->get_mat_format() == mat.get_mat_format());

  if (const HostMatrixMCSR<ValueType> *cast_mat = dynamic_cast<const HostMatrixMCSR<ValueType>*> (&mat)) {

    this->AllocateMCSR(cast_mat->nnz_, cast_mat->nrow_, cast_mat->ncol_);

    assert((this->nnz_  == cast_mat->nnz_)  &&
           (this->nrow_ == cast_mat->nrow_) &&
           (this->ncol_ == cast_mat->ncol_));

    if (this->nnz_ > 0) {

      _set_omp_backend_threads(this->local_backend_, this->nrow_);

#pragma omp parallel for
      for (int i=0; i<this->nrow_+1; ++i)
        this->mat_.row_offset[i] = cast_mat->mat_.row_offset[i];

#pragma omp parallel for
      for (int j=0; j<this->nnz_; ++j)
        this->mat_.col[j] = cast_mat->mat_.col[j];

#pragma omp parallel for
      for (int j=0; j<this->nnz_; ++j)
        this->mat_.val[j] = cast_mat->mat_.val[j];

    }

  } else {

    // Host matrix knows only host matrices
    // -> dispatching
    mat.CopyTo(this);

  }

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::CopyTo(BaseMatrix<ValueType> *mat) const {

  mat->CopyFrom(*this);

}

template <typename ValueType>
bool HostMatrixMCSR<ValueType>::ConvertFrom(const BaseMatrix<ValueType> &mat) {

  this->Clear();

  // empty matrix is empty matrix
  if (mat.get_nnz() == 0)
    return true;

  if (const HostMatrixMCSR<ValueType> *cast_mat = dynamic_cast<const HostMatrixMCSR<ValueType>*> (&mat)) {

    this->CopyFrom(*cast_mat);
    return true;

  }

  if (const HostMatrixCSR<ValueType> *cast_mat = dynamic_cast<const HostMatrixCSR<ValueType>*> (&mat)) {

    this->Clear();

    csr_to_mcsr(this->local_backend_.OpenMP_threads,
                cast_mat->nnz_, cast_mat->nrow_, cast_mat->ncol_,
                cast_mat->mat_, &this->mat_);

    this->nrow_ = cast_mat->nrow_;
    this->ncol_ = cast_mat->ncol_;
    this->nnz_  = cast_mat->nnz_;

    return true;

  }

  return false;

}

template <typename ValueType>
bool HostMatrixMCSR<ValueType>::ILU0Factorize(void) {

  assert(this->nrow_ == this->ncol_);
  assert(this->nnz_ > 0);

  int *diag_offset = NULL;
  int *nnz_entries = NULL;

  allocate_host(this->nrow_, &diag_offset);
  allocate_host(this->nrow_, &nnz_entries);

  for (int i=0; i<this->nrow_; ++i)
    nnz_entries[i] = 0;

  // ai = 0 to N loop over all rows
  for (int ai=0; ai<this->nrow_; ++ai) {

    int aj;
    int row_start = this->mat_.row_offset[ai];
    int row_end   = this->mat_.row_offset[ai+1];

    for (aj=row_start; aj<row_end; ++aj)
      nnz_entries[this->mat_.col[aj]] = aj;

    // Diagonal position
    nnz_entries[ai] = ai;

    // loop over ai-th row nnz entries
    for (aj=row_start; aj<row_end; ++aj) {

      if (this->mat_.col[aj] < ai) {

        int col_j  = this->mat_.col[aj];

        this->mat_.val[aj] /= this->mat_.val[col_j];

        // loop over upper offset pointer and do linear combination for nnz entry
        for (int ak = diag_offset[col_j]; ak<this->mat_.row_offset[col_j+1]; ++ak) {

          // if nnz at this position do linear combination
          if (nnz_entries[this->mat_.col[ak]] != 0)
            this->mat_.val[nnz_entries[this->mat_.col[ak]]] -= this->mat_.val[aj] * this->mat_.val[ak];

        }

      } else {
        break;
      }

    }

    // set diagonal pointer to diagonal element
    diag_offset[ai] = aj;

    // clear nnz entries
    for (aj=row_start; aj<row_end; ++aj)
      nnz_entries[this->mat_.col[aj]] = 0;

    nnz_entries[ai] = 0;

  }

  free_host(&diag_offset);
  free_host(&nnz_entries);

  return true;

}

template <typename ValueType>
bool HostMatrixMCSR<ValueType>::LUSolve(const BaseVector<ValueType> &in, BaseVector<ValueType> *out) const {

  assert(in.  get_size() >= 0);
  assert(out->get_size() >= 0);
  assert(in.  get_size() == this->ncol_);
  assert(out->get_size() == this->nrow_);

  const HostVector<ValueType> *cast_in = dynamic_cast<const HostVector<ValueType>*> (&in) ; 
  HostVector<ValueType> *cast_out      = dynamic_cast<      HostVector<ValueType>*> (out) ; 

  assert(cast_in != NULL);
  assert(cast_out!= NULL);

  // Solve L
  for (int ai=0; ai<this->nrow_; ++ai) {
    cast_out->vec_[ai] = cast_in->vec_[ai];
    for (int aj=this->mat_.row_offset[ai]; aj<this->mat_.row_offset[ai+1]; ++aj)
      if (this->mat_.col[aj] < ai)
        // under the diagonal
        cast_out->vec_[ai] -= this->mat_.val[aj] * cast_out->vec_[this->mat_.col[aj]];
      else
        // CSR should be sorted
        break;
  }

  // Solve U
  for (int ai=this->nrow_-1; ai>=0; --ai) {
    for (int aj=this->mat_.row_offset[ai]; aj<this->mat_.row_offset[ai+1]; ++aj)
      if (this->mat_.col[aj] > ai)
        cast_out->vec_[ai] -= this->mat_.val[aj] * cast_out->vec_[this->mat_.col[aj]];
    cast_out->vec_[ai] /= this->mat_.val[ai];
  }

  return true;

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::LUAnalyse(void) {
  // do nothing
}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::LUAnalyseClear(void) {
  // do nothing
}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::Apply(const BaseVector<ValueType> &in, BaseVector<ValueType> *out) const {

  if (this->nnz_ > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->ncol_);
    assert(out->get_size() == this->nrow_);

    const HostVector<ValueType> *cast_in = dynamic_cast<const HostVector<ValueType>*> (&in);
    HostVector<ValueType> *cast_out      = dynamic_cast<      HostVector<ValueType>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    _set_omp_backend_threads(this->local_backend_, this->nrow_);

    assert(this->nrow_ == this->ncol_);

#pragma omp parallel for
    for (int ai=0; ai<this->nrow_; ++ai) {

      ValueType sum = this->mat_.val[ai] * cast_in->vec_[ai];

      for (int aj=this->mat_.row_offset[ai]; aj<this->mat_.row_offset[ai+1]; ++aj)
        sum += this->mat_.val[aj] * cast_in->vec_[this->mat_.col[aj]];

      cast_out->vec_[ai] = sum;

    }

  }

}

template <typename ValueType>
void HostMatrixMCSR<ValueType>::ApplyAdd(const BaseVector<ValueType> &in, const ValueType scalar,
                                         BaseVector<ValueType> *out) const {

  if (this->nnz_ > 0) {

    assert(in.  get_size() >= 0);
    assert(out->get_size() >= 0);
    assert(in.  get_size() == this->ncol_);
    assert(out->get_size() == this->nrow_);

    const HostVector<ValueType> *cast_in = dynamic_cast<const HostVector<ValueType>*> (&in);
    HostVector<ValueType> *cast_out      = dynamic_cast<      HostVector<ValueType>*> (out);

    assert(cast_in != NULL);
    assert(cast_out!= NULL);

    _set_omp_backend_threads(this->local_backend_, this->nrow_);

    assert(this->nrow_ == this->ncol_);

#pragma omp parallel for
    for (int ai=0; ai<this->nrow_; ++ai) {

      cast_out->vec_[ai] += scalar*this->mat_.val[ai] * cast_in->vec_[ai];

      for (int aj=this->mat_.row_offset[ai]; aj<this->mat_.row_offset[ai+1]; ++aj)
        cast_out->vec_[ai] += scalar*this->mat_.val[aj] * cast_in->vec_[this->mat_.col[aj]];

    }

  }

}


template class HostMatrixMCSR<double>;
template class HostMatrixMCSR<float>;
#ifdef SUPPORT_COMPLEX
template class HostMatrixMCSR<std::complex<double> >;
template class HostMatrixMCSR<std::complex<float> >;
#endif

}
