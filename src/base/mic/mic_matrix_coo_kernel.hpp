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


#ifndef PARALUTION_MIC_MATRIX_COO_KERNEL_HPP_
#define PARALUTION_MIC_MATRIX_COO_KERNEL_HPP_

namespace paralution {

template <typename ValueType>
void spmv_coo(const int mic_dev, 
	      const int *row, const int *col, const ValueType *val,
	      const int nrow,
	      const int nnz,
	      const ValueType *in, ValueType *out);
template <typename ValueType>
void spmv_add_coo(const int mic_dev, 
		  const int *row, const int *col, const ValueType *val,
		  const int nrow,
		  const int nnz,
		  const ValueType scalar,
		  const ValueType *in, ValueType *out);

}

#endif // PARALUTION_BASE_MATRIX_COO_KERNEL_HPP_
