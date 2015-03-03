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


#ifndef PARALUTION_OCL_KERNELS_DENSE_HPP_
#define PARALUTION_OCL_KERNELS_DENSE_HPP_

namespace paralution {

const char *ocl_kernels_dense =
	"__kernel void kernel_dense_spmv(const int nrow, const int ncol, __global const ValueType *val,\n"
	"                                __global const ValueType *in, __global ValueType *out) {\n"
	"\n"
	"  int ai = get_global_id(0);\n"
	"\n"
	"  if (ai < nrow) {\n"
	"\n"
	"    ValueType sum = (ValueType)(0.0);\n"
	"\n"
	"    for (int aj=0; aj<ncol; ++aj)\n"
	"      sum += val[ai+aj*nrow] * in[aj];\n"
	"\n"
	"    out[ai] = sum;\n"
	"\n"
	"  }\n"
	"\n"
	"}\n"
	"\n"
// Replace column vector
	"__kernel void kernel_dense_replace_column_vector(__global const ValueType *vec, const int idx, const int nrow,\n"
	"                                                 __global ValueType *mat) {\n"
	"\n"
	"  int ai = get_global_id(0);\n"
	"\n"
	"  if(ai < nrow)\n"
	"    mat[ai+idx*nrow] = vec[ai];\n"
	"\n"
	"}\n"
	"\n"
// Replace row vector
	"__kernel void kernel_dense_replace_row_vector(__global const ValueType *vec, const int idx, const int nrow,\n"
	"                                              const int ncol, __global ValueType *mat) {\n"
	"\n"
	"  int aj = get_global_id(0);\n"
	"\n"
	"  if (aj < ncol)\n"
	"    mat[idx+aj*nrow] = vec[aj];\n"
	"\n"
	"}\n"
	"\n"
// Extract column vector
	"__kernel void kernel_dense_extract_column_vector(__global ValueType *vec, const int idx, const int nrow,\n"
	"                                                 __global const ValueType *mat) {\n"
	"\n"
	"  int ai = get_global_id(0);\n"
	"\n"
	"  if (ai < nrow)\n"
	"    vec[ai] = mat[ai+idx*nrow];\n"
	"\n"
	"}\n"
	"\n"
// Extract row vector
	"__kernel void kernel_dense_extract_row_vector(__global ValueType *vec, const int idx, const int nrow,\n"
	"                                              const int ncol, __global const ValueType *mat) {\n"
	"\n"
	"  int aj = get_global_id(0);\n"
	"\n"
	"  if (aj < ncol)\n"
	"    vec[aj] = mat[idx+aj*nrow];\n"
	"\n"
	"}\n"
	"\n"
;
}

#endif // PARALUTION_OCL_KERNELS_DENSE_HPP_
