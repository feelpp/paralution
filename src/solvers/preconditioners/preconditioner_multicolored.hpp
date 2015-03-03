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


#ifndef PARALUTION_PRECONDITIONER_MULTICOLORED_HPP_
#define PARALUTION_PRECONDITIONER_MULTICOLORED_HPP_

#include "../solver.hpp"
#include "preconditioner.hpp"
#include "../../base/local_vector.hpp"

#include <vector>

namespace paralution {

template <class OperatorType, class VectorType, typename ValueType>
class MultiColored : public Preconditioner<OperatorType, VectorType, ValueType> {

public:

  MultiColored();
  virtual ~MultiColored();

  virtual void Clear(void);  

  virtual void Build(void);

  /// Set a specific matrix type of the decomposed block matrices;
  /// if not set, CSR matrix format will be used
  virtual void SetPrecondMatrixFormat(const unsigned int mat_format);

  /// Set if the preconditioner should be decomposed or not
  virtual void SetDecomposition(const bool decomp);

  virtual void Solve(const VectorType &rhs,
                     VectorType *x);

protected:

  OperatorType *analyzer_op_;
  OperatorType *preconditioner_; 

  OperatorType ***preconditioner_block_; 

  VectorType **x_block_; 
  VectorType **diag_block_; 
  VectorType x_;
  VectorType diag_;

  Solver<OperatorType, VectorType, ValueType> **diag_solver_;

  int num_blocks_;
  int *block_sizes_;

  /// Keep the precond matrix in CSR or not
  bool op_mat_format_; 
  /// Precond matrix format
  unsigned int precond_mat_format_;

  /// Decompose the preconditioner into blocks or not
  bool decomp_;

  /// Extract the rhs into x under the permutation (see Analyse_()) and
  /// decompose x into block (x_block_[])
  virtual void ExtractRHSinX_(const VectorType &rhs,
                              VectorType *x);

  /// Solve the lower-triangular (left) matrix
  virtual void SolveL_(void) = 0;
  /// Solve the diagonal part (only for SGS)
  virtual void SolveD_(void) = 0;
  /// Solve the upper-trianguler (right) matrix
  virtual void SolveR_(void) = 0;

  /// Solve directly without block decomposition 
  virtual void Solve_(const VectorType &rhs,
                      VectorType *x) = 0;

  /// Insert the solution with backward permutation (from x_block_[])
  virtual void InsertSolution_(VectorType *x);

  
  /// Build the analyzing matrix
  virtual void Build_Analyser_(void); 
  /// Analyse the matrix (i.e. multi-coloring decomposition)
  virtual void Analyse_(void);
  /// Permute the preconditioning matrix
  virtual void Permute_(void);
  /// Factorize (i.e. build the preconditioner)
  virtual void Factorize_(void);
  /// Decompose the structure into blocks (preconditioner_block_[] for
  /// the preconditioning matrix; and x_block_[] for the x vector)
  virtual void Decompose_(void);
  /// Post-analyzing if the preconditioner is not decomposed
  virtual void PostAnalyse_(void);

  virtual void MoveToHostLocalData_(void);
  virtual void MoveToAcceleratorLocalData_(void) ;

};


}

#endif // PARALUTION_PRECONDITIONER_MULTICOLORED_HPP_
