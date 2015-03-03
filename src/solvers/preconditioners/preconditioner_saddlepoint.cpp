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
#include "preconditioner_saddlepoint.hpp"
#include "preconditioner.hpp"
#include "../solver.hpp"

#include "../../base/local_matrix.hpp"

#include "../../base/local_vector.hpp"

#include "../../utils/log.hpp"

#include <complex>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::DiagJacobiSaddlePointPrecond() {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::DiagJacobiSaddlePointPrecond()",
            "default constructor");

  this->size_ = 0;

  this->K_solver_ = NULL;
  this->S_solver_ = NULL;

  this->K_nrow_ = 0;
  this->K_nnz_  = 0;

}

template <class OperatorType, class VectorType, typename ValueType>
DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::~DiagJacobiSaddlePointPrecond() {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::~DiagJacobiSaddlePointPrecond()",
            "destructor");

  this->Clear();

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::Clear(void) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Clear()",
            this->build_);

  if (this->build_ == true) {

    this->A_.Clear();
    this->K_.Clear();
    this->S_.Clear();

    this->A_.ConvertToCSR();
    this->K_.ConvertToCSR();
    this->S_.ConvertToCSR();

    this->K_nrow_ = 0;
    this->K_nnz_  = 0;

    this->x_.Clear();
    this->x_1_.Clear();
    this->x_2_.Clear();

    this->rhs_.Clear();
    this->rhs_1_.Clear();
    this->rhs_1_.Clear();

    this->permutation_.Clear();

    if (this->K_solver_ != NULL)
      this->K_solver_->Clear();

    if (this->S_solver_ != NULL)
      this->S_solver_->Clear();

    this->size_ = 0;

    this->K_solver_ = NULL;
    this->S_solver_ = NULL;

    this->build_ = false ;

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::Print(void) const {

  if (this->build_ == true) {

    LOG_INFO("DiagJacobiSaddlePointPrecond preconditioner with " 
             << " ; S solver:");

    this->S_solver_->Print();

    LOG_INFO("and K solver:")
    this->K_solver_->Print();

  } else {

    LOG_INFO("DiagJacobiSaddlePointPrecond (I)LU preconditioner");

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::Set(Solver<OperatorType, VectorType, ValueType> &K_Solver,
                                                                            Solver<OperatorType, VectorType, ValueType> &S_Solver) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Set()",
            "");

  this->K_solver_ = &K_Solver;
  this->S_solver_ = &S_Solver;

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::Build(void) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Build()",
            this->build_ <<
            " #*# begin");

  assert(this->build_ == false);
  this->build_ = true ;

  assert(this->op_ != NULL);
  assert(this->K_solver_ != NULL);
  assert(this->S_solver_ != NULL);

  this->A_.CloneBackend(*this->op_);
  this->K_.CloneBackend(*this->op_);
  this->S_.CloneBackend(*this->op_);

  this->x_.CloneBackend(*this->op_);
  this->x_1_.CloneBackend(*this->op_);
  this->x_2_.CloneBackend(*this->op_);

  this->rhs_.CloneBackend(*this->op_);
  this->rhs_1_.CloneBackend(*this->op_);
  this->rhs_1_.CloneBackend(*this->op_);

  this->permutation_.CloneBackend(this->x_);

  this->A_.CloneFrom(*this->op_);

  //  this->A_.ConvertToCSR();

  this->A_.ZeroBlockPermutation(this->size_,
                                &this->permutation_);

  this->A_.Permute(this->permutation_);

  this->A_.ExtractSubMatrix(0, 0,
                       this->size_, this->size_,
                       &this->K_);

  OperatorType E, F;
  VectorType inv_K;

  E.CloneBackend(*this->op_);
  F.CloneBackend(*this->op_);
  inv_K.CloneBackend(*this->op_);

  this->A_.ExtractSubMatrix(0, this->size_,
                       this->size_, this->A_.get_ncol()-this->size_,
                       &F);

  this->A_.ExtractSubMatrix(this->size_, 0,
                       this->A_.get_nrow()-this->size_, this->size_,
                       &E);

  this->A_.Clear();

  // Construct solver for K
  this->K_solver_->SetOperator(this->K_);
  this->K_solver_->Build();

  // Construct solver for S
  // inv_K = inv(diag(K))
  this->K_.ExtractInverseDiagonal(&inv_K);

  // E = E * inv(diag(K))
  E.DiagonalMatrixMult(inv_K);

  // S = E * F
  this->S_.MatrixMult(E, F);

  this->S_solver_->SetOperator(this->S_);
  this->S_solver_->Build();

  this->x_.CloneBackend(*this->op_); 
  this->x_.Allocate("Permuted solution vector",
                    this->op_->get_nrow());

  this->rhs_.CloneBackend(*this->op_); 
  this->rhs_.Allocate("Permuted RHS vector",
                      this->op_->get_nrow());

  this->x_1_.CloneBackend(*this->op_); 
  this->x_1_.Allocate("Permuted solution vector",
                      this->size_);

  this->x_2_.CloneBackend(*this->op_); 
  this->x_2_.Allocate("Permuted solution vector",
                      this->op_->get_nrow()-this->size_);

  this->rhs_1_.CloneBackend(*this->op_); 
  this->rhs_1_.Allocate("Permuted solution vector",
                      this->size_);

  this->rhs_2_.CloneBackend(*this->op_); 
  this->rhs_2_.Allocate("Permuted solution vector",
                      this->op_->get_nrow()-this->size_);

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Build()",
            this->build_ <<
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::Solve(const VectorType &rhs,
                                                                  VectorType *x) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Solve()",
            " #*# begin");

  assert(this->build_ == true);

  this->rhs_.CopyFromPermute(rhs,
                             this->permutation_);

  this->rhs_1_.CopyFrom(this->rhs_, 
                      0,
                      0,
                      this->size_);

  this->rhs_2_.CopyFrom(this->rhs_, 
                        this->size_,
                        0,
                        this->rhs_.get_size() - this->size_);

  // Solve the first (K) block
  this->K_solver_->SolveZeroSol(this->rhs_1_,
                                &this->x_1_);

  // Solve the second (S) block
  this->S_solver_->SolveZeroSol(this->rhs_2_,
                                &this->x_2_);

  // Copy back
  this->x_.CopyFrom(this->x_1_, 
                    0,
                    0,
                    this->size_);

  this->x_.CopyFrom(this->x_2_, 
                    0,
                    this->size_,
                    this->rhs_.get_size() - this->size_);

  x->CopyFromPermuteBackward(this->x_,
                             this->permutation_);

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::Solve()",
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::MoveToHostLocalData_(void) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::MoveToHostLocalData_()",
            this->build_);

  this->A_.MoveToHost();
  this->K_.MoveToHost();
  this->S_.MoveToHost();

  this->x_.MoveToHost();
  this->x_1_.MoveToHost();
  this->x_2_.MoveToHost();

  this->rhs_.MoveToHost();
  this->rhs_1_.MoveToHost();
  this->rhs_2_.MoveToHost();

  this->permutation_.MoveToHost();

  if (this->K_solver_ != NULL)
    this->K_solver_->MoveToHost();

  if (this->S_solver_ != NULL)
    this->S_solver_->MoveToHost();

}

template <class OperatorType, class VectorType, typename ValueType>
void DiagJacobiSaddlePointPrecond<OperatorType, VectorType, ValueType>::MoveToAcceleratorLocalData_(void) {

  LOG_DEBUG(this, "DiagJacobiSaddlePointPrecond::MoveToAcceleratorLocalData_()",
            this->build_);

  this->A_.MoveToAccelerator();
  this->K_.MoveToAccelerator();
  this->S_.MoveToAccelerator();

  this->x_.MoveToAccelerator();
  this->x_1_.MoveToAccelerator();
  this->x_2_.MoveToAccelerator();

  this->rhs_.MoveToAccelerator();
  this->rhs_1_.MoveToAccelerator();
  this->rhs_2_.MoveToAccelerator();

  this->permutation_.MoveToAccelerator();
  
  if (this->K_solver_ != NULL)
    this->K_solver_->MoveToAccelerator();

  if (this->S_solver_ != NULL)
    this->S_solver_->MoveToAccelerator();

}


template class DiagJacobiSaddlePointPrecond< LocalMatrix<double>, LocalVector<double>, double >;
template class DiagJacobiSaddlePointPrecond< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class DiagJacobiSaddlePointPrecond< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class DiagJacobiSaddlePointPrecond< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

}
