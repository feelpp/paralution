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


#include "../utils/def.hpp"
#include "solver.hpp"

#include "../base/local_matrix.hpp"
#include "../base/local_stencil.hpp"
#include "../base/local_vector.hpp"

#include "../utils/log.hpp"
#include "../utils/math_functions.hpp"

#include <complex>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
Solver<OperatorType, VectorType, ValueType>::Solver() {

  LOG_DEBUG(this, "Solver::Solver()",
            "default constructor");

  this->op_  = NULL;
  this->precond_   = NULL;

  this->build_   = false;

}

template <class OperatorType, class VectorType, typename ValueType>
Solver<OperatorType, VectorType, ValueType>::~Solver() {

  LOG_DEBUG(this, "Solver::~Solver()",
            "destructor");

  // the preconditioner is defined outsite
  this->op_  = NULL;
  this->precond_   = NULL;

  this->build_   = false;

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::SetOperator(const OperatorType &op) {

  LOG_DEBUG(this, "Solver::SetOperator()",
            "");

  assert(this->build_ == false);

  this->op_  = &op;

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::ResetOperator(const OperatorType &op) {

  LOG_DEBUG(this, "Solver::ResetOperator()",
            "");

  // TODO
  //  assert(this->build_ != false);

  this->op_  = &op;

}


template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::SolveZeroSol(const VectorType &rhs,
                                                               VectorType *x) {

  LOG_DEBUG(this, "Solver::SolveZeroSol()",
            "");

  x->Zeros();
  this->Solve(rhs, x);

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::Build(void) {

  LOG_DEBUG(this, "Solver::Build()",
            "");

  // by default - nothing to build

  if (this->build_ == true)
    this->Clear();

  this->build_ = true;

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::ReBuildNumeric(void) {

  LOG_DEBUG(this, "Solver::ReBuildNumeric()",
            "");

  assert(this->build_ == true);

  // by default - just rebuild everything
  this->Clear();
  this->Build();

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::Clear(void) {

  LOG_DEBUG(this, "Solver::Clear()",
            "");

  if (this->precond_ != NULL)
    delete this->precond_;

  this->op_  = NULL;
  this->precond_   = NULL;

  this->build_   = false;

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::MoveToHost(void) {

  LOG_DEBUG(this, "Solver::MoveToHost()",
            "");

  if ( this->permutation_.get_size() > 0)
    this->permutation_.MoveToHost();

  if (this->precond_ != NULL)
    this->precond_->MoveToHost();

  // move all local data too
  this->MoveToHostLocalData_();

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::MoveToAccelerator(void) {

  LOG_DEBUG(this, "Solver::MoveToAccelerator()",
            "");

  if ( this->permutation_.get_size() > 0)
    this->permutation_.MoveToAccelerator();

  if (this->precond_ != NULL)
    this->precond_->MoveToAccelerator();

  // move all local data too
  this->MoveToAcceleratorLocalData_();

}

template <class OperatorType, class VectorType, typename ValueType>
void Solver<OperatorType, VectorType, ValueType>::Verbose(const int verb) {

  LOG_DEBUG(this, "Solver::Verbose()",
            verb);

  this->verb_ = verb; 

}



template <class OperatorType, class VectorType, typename ValueType>
IterativeLinearSolver<OperatorType, VectorType, ValueType>::IterativeLinearSolver() {

  LOG_DEBUG(this, "IterativeLinearSolver::IterativeLinearSolver()",
            "default constructor");

  this->verb_ = 1 ;

  this->res_norm_ = 2;
  this->index_ = -1;

}

template <class OperatorType, class VectorType, typename ValueType>
IterativeLinearSolver<OperatorType, VectorType, ValueType>::~IterativeLinearSolver() {

  LOG_DEBUG(this, "IterativeLinearSolver::~IterativeLinearSolver()",
            "");

}


template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::Init(const double abs_tol,
                                                                      const double rel_tol,
                                                                      const double div_tol,
                                                                      const int max_iter) {

  LOG_DEBUG(this, "IterativeLinearSolver::Init()",
            "abs_tol=" << abs_tol <<
            " rel_tol=" << rel_tol <<
            " div_tol=" << div_tol <<
            " max_iter=" << max_iter);

  this->iter_ctrl_.Init(abs_tol, rel_tol, div_tol, max_iter);

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::InitMaxIter(const int max_iter) {

  LOG_DEBUG(this, "IterativeLinearSolver::InitMaxIter()",
            max_iter);

  this->iter_ctrl_.InitMaximumIterations(max_iter);

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::InitTol(const double abs,
                                                                const double rel,
                                                                const double div) {

  LOG_DEBUG(this, "IterativeLinearSolver::Init()",
            "abs_tol=" << abs <<
            " rel_tol=" << rel <<
            " div_tol=" << div);


  this->iter_ctrl_.InitTolerance(abs, rel, div);

}

template <class OperatorType, class VectorType, typename ValueType>
int IterativeLinearSolver<OperatorType, VectorType, ValueType>::GetIterationCount(void) {

  LOG_DEBUG(this, "IterativeLinearSolver::GetIterationCount()",
            "");

  return this->iter_ctrl_.GetIterationCount();

}

template <class OperatorType, class VectorType, typename ValueType>
double IterativeLinearSolver<OperatorType, VectorType, ValueType>::GetCurrentResidual(void) {

  LOG_DEBUG(this, "IterativeLinearSolver::GetCurrentResidual()",
            "");

  return this->iter_ctrl_.GetCurrentResidual();

}

template <class OperatorType, class VectorType, typename ValueType>
int IterativeLinearSolver<OperatorType, VectorType, ValueType>::GetSolverStatus(void) {

  LOG_DEBUG(this, "IterativeLinearSolver::GetSolverStatus()",
            "");

  return this->iter_ctrl_.GetSolverStatus();

}

template <class OperatorType, class VectorType, typename ValueType>
int IterativeLinearSolver<OperatorType, VectorType, ValueType>::GetAmaxResidualIndex(void) {

  int ind = this->iter_ctrl_.GetAmaxResidualIndex();
  LOG_DEBUG(this, "IterativeLinearSolver::GetAmaxResidualIndex()",
            ind);

  if (this->res_norm_ != 3)
    LOG_INFO("Absolute maximum index of residual vector is only available when using Linf norm");

  return ind;

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::RecordResidualHistory(void) {

  LOG_DEBUG(this, "IterativeLinearSolver::RecordResidualHistory()",
            "");

  this->iter_ctrl_.RecordHistory();

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::RecordHistory(std::string filename) const {

  LOG_DEBUG(this, "IterativeLinearSolver::RecordHistory()",
            filename);

  this->iter_ctrl_.WriteHistoryToFile(filename);

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::Verbose(const int verb) {

  LOG_DEBUG(this, "IterativeLinearSolver::Verbose()",
            verb);


  this->verb_ = verb; 
  this->iter_ctrl_.Verbose(verb);

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::SetResidualNorm(const int resnorm) {

  LOG_DEBUG(this, "IterativeLinearSolver::SetResidualNorm()",
            resnorm);


  assert(resnorm == 1 || resnorm == 2 || resnorm == 3);

  this->res_norm_ = resnorm;

}

template <class OperatorType, class VectorType, typename ValueType>
ValueType IterativeLinearSolver<OperatorType, VectorType, ValueType>::Norm(const VectorType &vec) {

  LOG_DEBUG(this, "IterativeLinearSolver::Norm()",
            this->res_norm_);

  // L1 norm
  if (this->res_norm_ == 1)
    return vec.Asum();

  // L2 norm
  if (this->res_norm_ == 2)
    return vec.Norm();

  // Infinity norm
  if (this->res_norm_ == 3) {
    ValueType amax;
    this->index_ = vec.Amax(amax);
    return amax;
  }

  return 0;

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::Solve(const VectorType &rhs,
                                                              VectorType *x) {

  LOG_DEBUG(this, "IterativeLinearSolver::Solve()",
            "");

  assert(x != NULL);
  assert(x != &rhs);
  assert(this->op_ != NULL);
  assert(this->build_ == true);

  if (this->verb_ > 0) {
    this->PrintStart_();
    this->iter_ctrl_.PrintInit();
  }

  if (this->precond_ == NULL) {

    this->SolveNonPrecond_(rhs, x);

  } else {

    this->SolvePrecond_(rhs, x);

  }

  if (this->verb_ > 0) {
    this->iter_ctrl_.PrintStatus();
    this->PrintEnd_();
  }

}

template <class OperatorType, class VectorType, typename ValueType>
void IterativeLinearSolver<OperatorType, VectorType, ValueType>::SetPreconditioner(Solver<OperatorType, VectorType, ValueType> &precond){

    LOG_DEBUG(this, "IterativeLinearSolver::SetPreconditioner()",
            "");

  assert(this != &precond);
  this->precond_ = &precond;

}

template <class OperatorType, class VectorType, typename ValueType>
FixedPoint<OperatorType, VectorType, ValueType>::FixedPoint() {

  LOG_DEBUG(this, "FixedPoint::FixedPoint()",
            "default constructor");

  this->omega_ = 1.0;

}

template <class OperatorType, class VectorType, typename ValueType>
FixedPoint<OperatorType, VectorType, ValueType>::~FixedPoint() {

  LOG_DEBUG(this, "FixedPoint::~FixedPoint()",
            "destructor");


  this->Clear();

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::SetRelaxation(const ValueType omega) {

  LOG_DEBUG(this, "FixedPoint::SetRelaxation()",
            omega);


  this->omega_ = omega;

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::Print(void) const {

  if (this->precond_ == NULL) { 

    LOG_INFO("Fixed Point Iteration solver");

  } else {

    LOG_INFO("Fixed Point Iteration solver, with preconditioner:");
    this->precond_->Print();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::PrintStart_(void) const {

  assert(this->precond_ != NULL);
  LOG_INFO("Fixed Point Iteration solver starts with");
  this->precond_->Print();

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::PrintEnd_(void) const {

  LOG_INFO("Fixed Point Iteration solver ends");

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::ReBuildNumeric(void) {

  LOG_DEBUG(this, "FixedPoint::ReBuildNumeric()",
            this->build_);

  if (this->build_ == true) {

    this->x_old_.Zeros();
    this->x_res_.Zeros();

    this->iter_ctrl_.Clear();

    this->precond_->ReBuildNumeric();

  } else {

    this->Clear();
    this->Build();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::Clear(void) {

  LOG_DEBUG(this, "FixedPoint::Clear()",
            this->build_);


  if (this->build_ == true) {

    if (this->precond_ != NULL) {
      this->precond_->Clear();
      this->precond_   = NULL;
    }

    this->x_old_.Clear();
    this->x_res_.Clear();

    this->iter_ctrl_.Clear();

    this->build_ = false;

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::Build(void) {

  LOG_DEBUG(this, "FixedPoint::Build()",
            this->build_ <<
            " #*# begin");

  if (this->build_ == true)
    this->Clear();

  assert(this->build_ == false);
  assert(this->precond_ != NULL);
  assert(this->op_ != NULL);
  assert(this->op_->get_nrow() == this->op_->get_ncol());

  this->build_ = true;

  LOG_DEBUG(this, "FixedPoint::Build()",
            "allocating data");


  this->x_old_.CloneBackend(*this->op_);
  this->x_old_.Allocate("x_old", this->op_->get_nrow());

  this->x_res_.CloneBackend(*this->op_);
  this->x_res_.Allocate("x_res", this->op_->get_nrow());

  LOG_DEBUG(this, "FixedPoint::Build()",
            "building the preconditioner");


  this->precond_->SetOperator(*this->op_);

  this->precond_->Build();

  LOG_DEBUG(this, "FixedPoint::Build()",
            this->build_ <<
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::SolveNonPrecond_(const VectorType &rhs,
                                                                       VectorType *x) {

  LOG_INFO("Preconditioner for the Fixed Point method is required");
  FATAL_ERROR(__FILE__, __LINE__);

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::SolvePrecond_(const VectorType &rhs,
                                                                    VectorType *x) {

  LOG_DEBUG(this, "FixedPoint::SolvePrecond_()",
            " #*# begin");

  assert(x != NULL);
  assert(x != &rhs);
  assert(this->op_  != NULL);
  assert(this->precond_ != NULL);
  assert(this->build_ == true);

  if (this->iter_ctrl_.GetMaximumIterations() > 0) {

    // inital residual x_res = b - Ax
    this->op_->Apply(*x, &this->x_res_);
    this->x_res_.ScaleAdd(ValueType(-1.0), rhs);

    ValueType res = this->Norm(this->x_res_);

    if (this->iter_ctrl_.InitResidual(paralution_abs(res)) == false) {

      LOG_DEBUG(this, "FixedPoint::SolvePrecond_()",
                " #*# end");
      return;
    }

    // Solve M x_old = x_res
    this->precond_->SolveZeroSol(this->x_res_, &this->x_old_);

    // x = x + x_old
    x->ScaleAdd(ValueType(1.0), this->x_old_);

    // x_res = b - Ax
    this->op_->Apply(*x, &this->x_res_);
    this->x_res_.ScaleAdd(ValueType(-1.0), rhs); 

    res = this->Norm(this->x_res_);
    while (!this->iter_ctrl_.CheckResidual(paralution_abs(res), this->index_)) {

      // Solve M x_old = x_res
      this->precond_->SolveZeroSol(this->x_res_, &this->x_old_);

      // x = x + omega*x_old
      x->AddScale(this->x_old_, this->omega_);

      // x_res = b - Ax
      this->op_->Apply(*x, &this->x_res_);
      this->x_res_.ScaleAdd(ValueType(-1.0), rhs); 
      res = this->Norm(this->x_res_);

    }

  }

  LOG_DEBUG(this, "FixedPoint::SolvePrecond_()",
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::MoveToHostLocalData_(void) {

  LOG_DEBUG(this, "FixedPoint::MoveToHostLocalData_()",
            this->build_);

  if (this->build_ == true) {

    this->x_old_.MoveToHost();
    this->x_res_.MoveToHost();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void FixedPoint<OperatorType, VectorType, ValueType>::MoveToAcceleratorLocalData_(void) {

  LOG_DEBUG(this, "FixedPoint::MoveToAcceleratorLocalData__()",
            this->build_);

  if (this->build_ == true) {

    this->x_old_.MoveToAccelerator();
    this->x_res_.MoveToAccelerator();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
DirectLinearSolver<OperatorType, VectorType, ValueType>::DirectLinearSolver() {

  LOG_DEBUG(this, "DirectLinearSolver::DirectLinearSolver()",
            "default constructor");

  this->verb_ = 1 ;

}

template <class OperatorType, class VectorType, typename ValueType>
DirectLinearSolver<OperatorType, VectorType, ValueType>::~DirectLinearSolver() {

  LOG_DEBUG(this, "DirectLinearSolver::~DirectLinearSolver()",
            "");

}

template <class OperatorType, class VectorType, typename ValueType>
void DirectLinearSolver<OperatorType, VectorType, ValueType>::Verbose(const int verb) {

  LOG_DEBUG(this, "DirectLinearSolver::Verbose()",
            verb);

  this->verb_ = verb; 

}

template <class OperatorType, class VectorType, typename ValueType>
void DirectLinearSolver<OperatorType, VectorType, ValueType>::Solve(const VectorType &rhs,
                                                              VectorType *x) {

  LOG_DEBUG(this, "DirectLinearSolver::Solve()",
            "");

  assert(x != NULL);
  assert(x != &rhs);
  assert(this->op_ != NULL);
  assert(this->build_ == true);

  if (this->verb_ > 0)
    this->PrintStart_();

  this->Solve_(rhs, x);

  if (this->verb_ > 0)
    this->PrintEnd_();

}


template class Solver< LocalMatrix<double>, LocalVector<double>, double >;
template class Solver< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class Solver< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class Solver< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class IterativeLinearSolver< LocalMatrix<double>, LocalVector<double>, double >;
template class IterativeLinearSolver< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class IterativeLinearSolver< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class IterativeLinearSolver< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class FixedPoint< LocalMatrix<double>, LocalVector<double>, double >;
template class FixedPoint< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class FixedPoint< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class FixedPoint< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class DirectLinearSolver< LocalMatrix<double>, LocalVector<double>, double >;
template class DirectLinearSolver< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class DirectLinearSolver< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class DirectLinearSolver< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class Solver< LocalStencil<double>, LocalVector<double>, double >;
template class Solver< LocalStencil<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class Solver< LocalStencil<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class Solver< LocalStencil<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class IterativeLinearSolver< LocalStencil<double>, LocalVector<double>, double >;
template class IterativeLinearSolver< LocalStencil<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class IterativeLinearSolver< LocalStencil<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class IterativeLinearSolver< LocalStencil<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class FixedPoint< LocalStencil<double>, LocalVector<double>, double >;
template class FixedPoint< LocalStencil<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class FixedPoint< LocalStencil<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class FixedPoint< LocalStencil<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class DirectLinearSolver< LocalStencil<double>, LocalVector<double>, double >;
template class DirectLinearSolver< LocalStencil<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class DirectLinearSolver< LocalStencil<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class DirectLinearSolver< LocalStencil<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

}
