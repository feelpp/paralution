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
#include "preconditioner_multielimination.hpp"
#include "preconditioner.hpp"
#include "../solver.hpp"

#include "../../base/local_matrix.hpp"

#include "../../base/local_vector.hpp"

#include "../../utils/log.hpp"
#include "../../utils/math_functions.hpp"

#include <complex>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
MultiElimination<OperatorType, VectorType, ValueType>::MultiElimination() {

  LOG_DEBUG(this, "MultiElimination::MultiElimination()",
            "default constructor");

  this->diag_solver_init_ = false;
  this->level_ = -1;
  this->drop_off_ = double(0.0);
  this->size_ = 0;

  this->AA_me_ = NULL;
  this->AA_solver_ = NULL;

  this->AA_nrow_ = 0;
  this->AA_nnz_  = 0;

  this->op_mat_format_ = false;
  this->precond_mat_format_ = CSR;

}

template <class OperatorType, class VectorType, typename ValueType>
MultiElimination<OperatorType, VectorType, ValueType>::~MultiElimination() {

  LOG_DEBUG(this, "MultiElimination::~MultiElimination()",
            "destructor");

  this->Clear();

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::Clear(void) {

  LOG_DEBUG(this, "MultiElimination::Clear()",
            this->build_);

  if (this->build_ == true) {

    this->A_.Clear();
    this->D_.Clear();
    this->C_.Clear();
    this->E_.Clear();
    this->F_.Clear();
    this->AA_.Clear();

    this->A_.ConvertToCSR();
    this->D_.ConvertToCSR();
    this->C_.ConvertToCSR();
    this->E_.ConvertToCSR();
    this->F_.ConvertToCSR();
    this->AA_.ConvertToCSR();

    this->AA_nrow_ = 0;
    this->AA_nnz_  = 0;

    this->x_.Clear();
    this->x_1_.Clear();
    this->x_2_.Clear();

    this->rhs_.Clear();
    this->rhs_1_.Clear();
    this->rhs_1_.Clear();

    this->permutation_.Clear();

   if (this->AA_solver_ != NULL)
      this->AA_solver_->Clear();

    if (this->AA_me_ != NULL)
      delete this->AA_me_;

    this->diag_solver_init_ = false;
    this->level_ = -1;
    this->drop_off_ = double(0.0);
    this->size_ = 0;

    this->AA_me_ = NULL;
    this->AA_solver_ = NULL;

    this->op_mat_format_ = false;
    this->precond_mat_format_ = CSR;

    this->build_ = false ;

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::Print(void) const {

  if (this->build_ == true) {

    LOG_INFO("MultiElimination (I)LU preconditioner with " << this->get_level() 
             << " levels; diagonal size = " << this->get_size_diag_block() 
             << " ; drop tol  = " << this->drop_off_ 
             << " ; last-block size = " << this->AA_nrow_
             << " ; last-block nnz = " << this->AA_nnz_
             << " ; last-block solver:");

    this->AA_solver_->Print();

  } else {

    LOG_INFO("MultiElimination (I)LU preconditioner");

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::Set(Solver<OperatorType, VectorType, ValueType> &AA_Solver,
                                                                const int level, const double drop_off) {

  LOG_DEBUG(this, "MultiElimination::Set()",
            "level=" << level <<
            " drop_off=" << drop_off);

  assert(level >= 0);

  this->level_ = level;
  this->AA_solver_ = &AA_Solver;
  this->drop_off_ = drop_off;

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::SetPrecondMatrixFormat(const unsigned int mat_format) {

  LOG_DEBUG(this, "MultiElimination::SetPrecondMatrixFormat()",
            mat_format);

  this->op_mat_format_ = true;
  this->precond_mat_format_ = mat_format;

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::Build(void) {

  LOG_DEBUG(this, "MultiElimination::Build()",
            this->build_ <<
            " #*# begin");

  assert(this->build_ == false);
  this->build_ = true ;

  assert(this->op_ != NULL);
  assert(this->AA_solver_ != NULL);

  this->A_.CloneBackend(*this->op_);
  this->D_.CloneBackend(*this->op_);
  this->C_.CloneBackend(*this->op_);
  this->E_.CloneBackend(*this->op_);
  this->F_.CloneBackend(*this->op_);
  this->AA_.CloneBackend(*this->op_);

  this->inv_vec_D_.CloneBackend(*this->op_);
  this->vec_D_.CloneBackend(*this->op_);

  this->x_.CloneBackend(*this->op_);
  this->x_1_.CloneBackend(*this->op_);
  this->x_2_.CloneBackend(*this->op_);

  this->rhs_.CloneBackend(*this->op_);
  this->rhs_1_.CloneBackend(*this->op_);
  this->rhs_1_.CloneBackend(*this->op_);

  this->permutation_.CloneBackend(this->x_);

  this->A_.CloneFrom(*this->op_);

  //  this->A_.ConvertToCSR();

  this->A_.MaximalIndependentSet(this->size_,
                                   &this->permutation_);

  this->A_.Permute(this->permutation_);

  this->A_.ExtractSubMatrix(0, 0,
                       this->size_, this->size_,
                       &this->D_);

  this->A_.ExtractSubMatrix(0, this->size_,
                       this->size_, this->A_.get_ncol()-this->size_,
                       &this->F_);

  this->A_.ExtractSubMatrix(this->size_, 0,
                       this->A_.get_nrow()-this->size_, this->size_,
                       &this->E_);

  this->A_.ExtractSubMatrix(this->size_, this->size_,
                       this->A_.get_nrow()-this->size_, this->A_.get_ncol()-this->size_,
                       &this->C_);

  this->A_.Clear();

  this->D_.ExtractInverseDiagonal(&this->inv_vec_D_);
  this->D_.ExtractDiagonal(&this->vec_D_);

  this->E_.DiagonalMatrixMult(this->inv_vec_D_); // E =  E * D^-1

  this->AA_.MatrixMult(this->E_, this->F_); // AA = E * D^-1 * F

  //  this->AA_.ScaleDiagonal(-1.0);
  //  this->AA_.ScaleOffDiagonal(-1.0);
  //  this->AA_.MatrixAdd(this->C_);

  // AA = C - E D^-1 F
  this->AA_.MatrixAdd(this->C_,
                      ValueType(-1.0),
                      ValueType(1.0),
                      true); // build new structure

  this->C_.Clear();

  if (this->drop_off_ > double(0.0))
    this->AA_.Compress(this->drop_off_);

  this->AA_nrow_ = this->AA_.get_nrow();
  this->AA_nnz_  = this->AA_.get_nnz();

  if (this->level_ > 1) {

    // Go one level lower

    this->AA_me_ = new MultiElimination<OperatorType, VectorType, ValueType>;
    this->AA_me_->SetOperator(this->AA_);
    this->AA_me_->Set(*this->AA_solver_,
                      this->level_-1,
                      this->drop_off_);

    this->AA_me_->Build();

    this->AA_solver_ = this->AA_me_;

  } else {

    // level == 0
    // set solver

    this->AA_solver_->SetOperator(this->AA_);
    this->AA_solver_->Build();

  }

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

  if (this->level_ > 1) { 
    this->AA_.Clear();
  }

  // Clone the format 
  // e.g. the block matrices will have the same format as this->op_
  if (this->op_mat_format_ == true) {
    A_.ConvertTo(this->precond_mat_format_);
    D_.ConvertTo(this->precond_mat_format_);
    E_.ConvertTo(this->precond_mat_format_);
    F_.ConvertTo(this->precond_mat_format_);
    //    C_.ConvertTo(this->precond_mat_format_);
    //    AA_.ConvertTo(this->precond_mat_format_);
  }

  LOG_DEBUG(this, "MultiElimination::Build()",
            this->build_ <<
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::Solve(const VectorType &rhs,
                                                                  VectorType *x) {

  LOG_DEBUG(this, "MultiElimination::Solve()",
            " #*# begin");

  assert(this->build_ == true);

  LOG_DEBUG(this, "MultiElimination::Solve()",
            "level = " << this->get_level() << " with size=" << this->get_size_diag_block() );

  this->rhs_.CopyFromPermute(rhs, this->permutation_);

  this->x_1_.CopyFrom(this->rhs_, 
                      0,
                      0,
                      this->size_);

  this->rhs_2_.CopyFrom(this->rhs_, 
                      this->size_,
                      0,
                      this->rhs_.get_size() - this->size_);

  // Solve L  
  this->E_.ApplyAdd(this->x_1_, ValueType(-1.0), &this->rhs_2_);

  // Solve R
  this->AA_solver_->SolveZeroSol(this->rhs_2_,
                                 &this->x_2_);

  this->F_.ApplyAdd(this->x_2_, ValueType(-1.0), &this->x_1_);

  this->x_1_.PointWiseMult(this->inv_vec_D_);

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

  LOG_DEBUG(this, "MultiElimination::Solve()",
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::MoveToHostLocalData_(void) {

  LOG_DEBUG(this, "MultiElimination::MoveToHostLocalData_()",
            this->build_);

  this->A_.MoveToHost();
  this->D_.MoveToHost();
  this->C_.MoveToHost();
  this->E_.MoveToHost();
  this->F_.MoveToHost();
  this->AA_.MoveToHost();

  this->x_.MoveToHost();
  this->x_1_.MoveToHost();
  this->x_2_.MoveToHost();

  this->rhs_.MoveToHost();
  this->rhs_1_.MoveToHost();
  this->rhs_2_.MoveToHost();

  this->inv_vec_D_.MoveToHost();

  this->permutation_.MoveToHost();

  if (this->AA_me_ != NULL)
    this->AA_me_->MoveToHost();

  if (this->AA_solver_ != NULL)
    this->AA_solver_->MoveToHost();

}

template <class OperatorType, class VectorType, typename ValueType>
void MultiElimination<OperatorType, VectorType, ValueType>::MoveToAcceleratorLocalData_(void) {

  LOG_DEBUG(this, "MultiElimination::MoveToAcceleratorLocalData_()",
            this->build_);

  this->A_.MoveToAccelerator();
  this->D_.MoveToAccelerator();
  this->C_.MoveToAccelerator();
  this->E_.MoveToAccelerator();
  this->F_.MoveToAccelerator();
  this->AA_.MoveToAccelerator();

  this->x_.MoveToAccelerator();
  this->x_1_.MoveToAccelerator();
  this->x_2_.MoveToAccelerator();

  this->rhs_.MoveToAccelerator();
  this->rhs_1_.MoveToAccelerator();
  this->rhs_2_.MoveToAccelerator();

  this->inv_vec_D_.MoveToAccelerator();

  this->permutation_.MoveToAccelerator();
  
  if (this->AA_me_ != NULL)
    this->AA_me_->MoveToAccelerator();

  if (this->AA_solver_ != NULL)
    this->AA_solver_->MoveToAccelerator();

}


template class MultiElimination< LocalMatrix<double>, LocalVector<double>, double >;
template class MultiElimination< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class MultiElimination< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class MultiElimination< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

}
