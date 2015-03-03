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
#include "chebyshev.hpp"
#include "iter_ctrl.hpp"

#include "../base/local_matrix.hpp"
#include "../base/local_stencil.hpp"
#include "../base/local_vector.hpp"

#include "../utils/log.hpp"
#include "../utils/math_functions.hpp"

#include <math.h>
#include <complex>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
Chebyshev<OperatorType, VectorType, ValueType>::Chebyshev() {

  LOG_DEBUG(this, "Chebyshev::Chebyshev()",
            "default constructor");

  this->init_lambda_ = false;

}

template <class OperatorType, class VectorType, typename ValueType>
Chebyshev<OperatorType, VectorType, ValueType>::~Chebyshev() {

  LOG_DEBUG(this, "Chebyshev::~Chebyshev()",
            "destructor");

  this->Clear();

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::Set(const ValueType lambda_min, 
                                                         const ValueType lambda_max) {

  LOG_DEBUG(this, "Chebyshev::Set()",
            "lambda_min="  << lambda_min <<
            " lambda_max=" << lambda_max);


  this->lambda_min_ = lambda_min;
  this->lambda_max_ = lambda_max;

  this->init_lambda_ = true;

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::Print(void) const {
  
  if (this->precond_ == NULL) { 
    
    LOG_INFO("Chebyshev solver");
    
  } else {
    
    LOG_INFO("PChebyshev solver, with preconditioner:");
    this->precond_->Print();

  }

  
}


template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::PrintStart_(void) const {

  if (this->precond_ == NULL) { 

    LOG_INFO("Chebyshev (non-precond) linear solver starts");

  } else {

    LOG_INFO("PChebyshev solver starts, with preconditioner:");
    this->precond_->Print();

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::PrintEnd_(void) const {

  if (this->precond_ == NULL) { 

    LOG_INFO("Chebyshev (non-precond) ends");

  } else {

    LOG_INFO("PChebyshev ends");

  }

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::Build(void) {

  LOG_DEBUG(this, "Chebyshev::Build()",
            this->build_ <<
            " #*# begin");

  if (this->build_ == true)
    this->Clear();

  assert(this->build_ == false);
  this->build_ = true;

  assert(this->op_ != NULL);

  assert(this->op_->get_nrow() == this->op_->get_ncol());
  assert(this->op_->get_nrow() > 0);

  if (this->precond_ != NULL) {
    
    this->precond_->SetOperator(*this->op_);
    this->precond_->Build();
    
    this->z_.CloneBackend(*this->op_);
    this->z_.Allocate("z", this->op_->get_nrow());
    
  } 

  this->r_.CloneBackend(*this->op_);
  this->r_.Allocate("r", this->op_->get_nrow());
  
  this->p_.CloneBackend(*this->op_);
  this->p_.Allocate("p", this->op_->get_nrow());

  LOG_DEBUG(this, "Chebyshev::Build()",
            this->build_ <<
            " #*# end");


}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::Clear(void) {

  LOG_DEBUG(this, "Chebyshev::Clear()",
            this->build_);


  if (this->build_ == true) {

    if (this->precond_ != NULL) {
      this->precond_->Clear();
      this->precond_   = NULL;
    }

    this->r_.Clear();
    this->z_.Clear();
    this->p_.Clear();
    
    this->iter_ctrl_.Clear();
    
    this->build_ = false;
    this->init_lambda_ = false;
  }

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::MoveToHostLocalData_(void) {

  LOG_DEBUG(this, "Chebyshev::MoveToHostLocalData_()",
            this->build_);


  if (this->build_ == true) {

    this->r_.MoveToHost();
    this->p_.MoveToHost();
 
    if (this->precond_ != NULL) {
      this->z_.MoveToHost();
    }
    
  }

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::MoveToAcceleratorLocalData_(void) {

  LOG_DEBUG(this, "Chebyshev::MoveToAcceleratorLocalData_()",
            this->build_);

  if (this->build_ == true) {

    this->r_.MoveToAccelerator();
    this->p_.MoveToAccelerator();
 
    if (this->precond_ != NULL) {
      this->z_.MoveToAccelerator();
    }
    
  }

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::SolveNonPrecond_(const VectorType &rhs,
                                                                      VectorType *x) {

  LOG_DEBUG(this, "Chebyshev::SolveNonPrecond_()",
            " #*# begin");

  assert(x != NULL);
  assert(x != &rhs);
  assert(this->op_  != NULL);
  assert(this->precond_  == NULL);
  assert(this->build_ == true);
  assert(this->init_lambda_ == true);

  const OperatorType *op = this->op_;

  VectorType *r = &this->r_;
  VectorType *p = &this->p_;

  ValueType alpha, beta;
  ValueType d = (this->lambda_max_ + this->lambda_min_)/ValueType(2.0);
  ValueType c = (this->lambda_max_ - this->lambda_min_)/ValueType(2.0);


  // initial residual = b - Ax
  op->Apply(*x, r);
  r->ScaleAdd(ValueType(-1.0), rhs);

  ValueType res = this->Norm(*r);

  if (this->iter_ctrl_.InitResidual(paralution_abs(res)) == false) {

    LOG_DEBUG(this, "Chebyshev::SolveNonPrecond_()",
              " #*# end");

    return;
  }

  // p = r
  p->CopyFrom(*r);

  alpha = ValueType(2.0) / d;

  // x = x + alpha*p
  x->AddScale(*p, alpha);

  // compute residual = b - Ax
  op->Apply(*x, r);
  r->ScaleAdd(ValueType(-1.0), rhs);

  res = this->Norm(*r);
  while (!this->iter_ctrl_.CheckResidual(paralution_abs(res), this->index_)) {

    beta = (c*alpha/ValueType(2.0))*(c*alpha/ValueType(2.0));

    alpha = ValueType(1.0) / (d - beta);

    // p = beta*p + r
    p->ScaleAdd(beta, *r);

    // x = x + alpha*p
    x->AddScale(*p, alpha);

    // compute residual = b - Ax
    op->Apply(*x, r);
    r->ScaleAdd(ValueType(-1.0), rhs);
    res = this->Norm(*r);
  }

  LOG_DEBUG(this, "Chebyshev::SolveNonPrecond_()",
            " #*# end");

}

template <class OperatorType, class VectorType, typename ValueType>
void Chebyshev<OperatorType, VectorType, ValueType>::SolvePrecond_(const VectorType &rhs,
                                                                   VectorType *x) {

  LOG_DEBUG(this, "Chebyshev::SolvePrecond_()",
            " #*# begin");

  assert(x != NULL);
  assert(x != &rhs);
  assert(this->op_  != NULL);
  assert(this->precond_ != NULL);
  assert(this->build_ == true);
  assert(this->init_lambda_ == true);

  const OperatorType *op = this->op_;

  VectorType *r = &this->r_;
  VectorType *z = &this->z_;
  VectorType *p = &this->p_;

  ValueType alpha, beta;
  ValueType d = (this->lambda_max_ + this->lambda_min_)/ValueType(2.0);
  ValueType c = (this->lambda_max_ - this->lambda_min_)/ValueType(2.0);

  // initial residual = b - Ax
  op->Apply(*x, r);
  r->ScaleAdd(ValueType(-1.0), rhs);

  ValueType res = this->Norm(*r); 

  if (this->iter_ctrl_.InitResidual(paralution_abs(res)) == false) {

    LOG_DEBUG(this, "Chebyshev::SolvePrecond_()",
              " #*# end");

    return;
  }

  // Solve Mz=r
  this->precond_->SolveZeroSol(*r, z);

  // p = z 
  p->CopyFrom(*z);

  alpha = ValueType(2.0) / d;

  // x = x + alpha*p
  x->AddScale(*p, alpha);

  // compute residual = b - Ax
  op->Apply(*x, r);
  r->ScaleAdd(ValueType(-1.0), rhs);
  res = this->Norm(*r); 

  while (!this->iter_ctrl_.CheckResidual(paralution_abs(res), this->index_)) {

    // Solve Mz=r
    this->precond_->SolveZeroSol(*r, z);

    beta = (c*alpha/ValueType(2.0))*(c*alpha/ValueType(2.0));

    alpha = ValueType(1.0) / (d - beta);

    // p = beta*p + z
    p->ScaleAdd(beta, *z);

    // x = x + alpha*p
    x->AddScale(*p, alpha);

    // compute residual = b - Ax
    op->Apply(*x, r);
    r->ScaleAdd(ValueType(-1.0), rhs);
    res = this->Norm(*r);

  }

  LOG_DEBUG(this, "Chebyshev::SolvePrecond_()",
            " #*# end");

}


template class Chebyshev< LocalMatrix<double>, LocalVector<double>, double >;
template class Chebyshev< LocalMatrix<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class Chebyshev< LocalMatrix<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class Chebyshev< LocalMatrix<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

template class Chebyshev< LocalStencil<double>, LocalVector<double>, double >;
template class Chebyshev< LocalStencil<float>,  LocalVector<float>, float >;
#ifdef SUPPORT_COMPLEX
template class Chebyshev< LocalStencil<std::complex<double> >,  LocalVector<std::complex<double> >, std::complex<double> >;
template class Chebyshev< LocalStencil<std::complex<float> >,  LocalVector<std::complex<float> >, std::complex<float> >;
#endif

}
