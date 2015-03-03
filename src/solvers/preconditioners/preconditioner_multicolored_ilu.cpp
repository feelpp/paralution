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
#include "preconditioner_multicolored_ilu.hpp"
#include "preconditioner_multicolored.hpp"
#include "preconditioner.hpp"
#include "../solver.hpp"

#include "../../base/local_matrix.hpp"

#include "../../base/local_vector.hpp"

#include "../../utils/log.hpp"

#include <complex>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
MultiColoredILU<OperatorType, VectorType, ValueType>::MultiColoredILU() {

  LOG_DEBUG(this, "MultiColoredILU::MultiColoredILU()",
            "default constructor");

  this->q_ = 1 ;
  this->p_ = 0 ;
  this->level_ = true;
  this->nnz_ = 0 ;

}

template <class OperatorType, class VectorType, typename ValueType>
MultiColoredILU<OperatorType, VectorType, ValueType>::~MultiColoredILU() {

  LOG_DEBUG(this, "MultiColoredILU::~MultiColoredILU()",
            "destructor");

  this->Clear();

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Print(void) const {

  LOG_INFO("Multicolored ILU preconditioner (power(q)-pattern method), ILU(" << this->p_ << "," << this->q_ << ")");  

  if (this->build_ == true) {
    LOG_INFO("number of colors = " << this->num_blocks_ << "; ILU nnz = " << this->nnz_ );
  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Set(const int p) {

  LOG_DEBUG(this, "MultiColoredILU::Set()",
            p);

  assert(this->build_ == false);
  assert(p >= 0);

  this->p_ = p ;
  this->q_ = p+1 ;
  
} 

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Set(const int p, const int q, const bool level) {

  LOG_DEBUG(this, "MultiColoredILU::Set()",
            "p=" << p <<
            " q=" << q <<
            " level=" << level);

  assert(this->build_ == false);
  assert(p >= 0);
  assert(q >= 1);

  this->p_     = p ;
  this->q_     = q ;
  this->level_ = level;
  
} 

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Build_Analyser_(void) {

  LOG_DEBUG(this, "MultiColoredILU::Build_Analyser_()",
            this->build_);  

  assert(this->op_ != NULL);

  if ( this->q_ > 1 ) {

    this->analyzer_op_ = new OperatorType;
    this->analyzer_op_->CloneFrom(*this->op_);

    this->analyzer_op_->SymbolicPower(this->q_);

  } else {

    this->analyzer_op_ = NULL;

  }

  this->preconditioner_ = new OperatorType ;
  this->preconditioner_->CloneFrom(*this->op_);

  this->permutation_.CloneBackend(*this->op_);

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::PostAnalyse_(void) {

  LOG_DEBUG(this, "MultiColoredILU::PostAnalyse_()",
            this->build_);

  assert(this->build_ == true);
  this->preconditioner_->LUAnalyse();

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Factorize_(void) {

  LOG_DEBUG(this, "MultiColoredILU::Factorize_()",
            this->build_);

  this->preconditioner_->ILUpFactorize(this->p_, this->level_);

  this->nnz_ = this->preconditioner_->get_nnz();

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::ReBuildNumeric(void) {

  LOG_DEBUG(this, "MultiColoredILU::ReBuildNumeric()",
            this->build_);

  if (this->decomp_ == false) {

    this->preconditioner_->PermuteBackward(this->permutation_);

    this->preconditioner_->Zeros();
    this->preconditioner_->MatrixAdd(*this->op_,
                                     ValueType(0.0),
                                     ValueType(1.0),
                                     false);

    this->preconditioner_->Permute(this->permutation_);

    this->preconditioner_->ILU0Factorize();
    this->preconditioner_->LUAnalyse();

  } else {

    if (this->preconditioner_ != NULL) {
      this->preconditioner_->Clear();
      delete this->preconditioner_;
    }

    for(int i=0; i<this->num_blocks_; ++i) {
        
      delete this->x_block_[i] ;
      delete this->diag_block_[i];
      delete this->diag_solver_[i];

      for(int j=0; j<this->num_blocks_; ++j)
        delete this->preconditioner_block_[i][j];

      delete[] this->preconditioner_block_[i];

    }

    delete[] this->preconditioner_block_;
    delete[] this->x_block_;
    delete[] this->diag_block_;
    delete[] this->diag_solver_;

    this->preconditioner_ = new OperatorType ;
    this->preconditioner_->CloneFrom(*this->op_);

    this->Permute_();
    this->Factorize_();
    this->Decompose_();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::SolveL_(void) {

  LOG_DEBUG(this, "MultiColoredILU::SolveL_()",
            "");

  assert(this->build_ == true);

  for (int i=0; i<this->num_blocks_; ++i) {

    for (int j=0; j<i; ++j)
      this->preconditioner_block_[i][j]->ApplyAdd(*this->x_block_[j],
                                                  ValueType(-1.0),
                                                  this->x_block_[i]);

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::SolveD_(void) {
}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::SolveR_(void) {

  LOG_DEBUG(this, "MultiColoredILU::SolveR_()",
            "");

  assert(this->build_ == true);

  for (int i=this->num_blocks_-1; i>=0; --i) {

    for (int j=this->num_blocks_-1; j>i; --j)
      this->preconditioner_block_[i][j]->ApplyAdd(*this->x_block_[j],
                                                  ValueType(-1.0),
                                                  this->x_block_[i]);

    this->diag_solver_[i]->Solve(*this->x_block_[i],
                                 this->x_block_[i]);

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiColoredILU<OperatorType, VectorType, ValueType>::Solve_(const VectorType &rhs,
                                                              VectorType *x) {

  LOG_DEBUG(this, "MultiColoredILU::Solve_()",
            "");

    x->CopyFromPermute(rhs,
                       this->permutation_);   

    this->preconditioner_->LUSolve(*x, &this->x_);

    x->CopyFromPermuteBackward(this->x_,
                               this->permutation_);

}


template class MultiColoredILU< LocalMatrix<double>, LocalVector<double>, double >;
template class MultiColoredILU< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class MultiColoredILU< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class MultiColoredILU< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

}
