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


#ifndef PARALUTION_MIC_ALLOCATE_FREE_HPP_
#define PARALUTION_MIC_ALLOCATE_FREE_HPP_

namespace paralution {

template <typename DataType>
void allocate_mic(const int mic_dev, const int size, DataType **ptr);

template <typename DataType>
void free_mic(const int mic_dev, DataType **ptr);

template <typename DataType>
void set_to_zero_mic(const int mic_dev, const int size, DataType *ptr);

template <typename DataType>
void set_to_one_mic(const int mic_dev, const int size, DataType *ptr);


};

#endif // PARALUTION_MIC_ALLOCATE_FREE_HPP_



