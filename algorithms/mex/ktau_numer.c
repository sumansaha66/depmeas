/*==========================================================
 * ktau_numer.c - 
 *
 * Computes the numerator for Kendall's Tau
 *
 * The calling syntax is:
 *
 *		s = ktau_numer(arr1,arr2)
 *
 * This is a MEX-file for MATLAB.  The library functions come from:
 * <https://afni.nimh.nih.gov/pub/dist/src/ktaub.c>
 * A copy of the license disclaimer is provided here again for redundancy:
 *
 *-------------------------------------------------------------------------
 * This file contains code to calculate Kendall's Tau in O(N log N) time in
 * a manner similar to the following reference:
 *
 * A Computer Method for Calculating Kendall's Tau with Ungrouped Data
 * William R. Knight Journal of the American Statistical Association,
 * Vol. 61, No. 314, Part 1 (Jun., 1966), pp. 436-439
 *
 * Copyright 2010 David Simcha
 *
 * License:
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 *========================================================*/

#include <string.h>
#include "mex.h"

/*-------------------------------------------------------------------------*/
/* Sorts in place, returns the bubble sort distance between the input array
 * and the sorted array.
 */

static int insertionSort(double *arr, int len)
{
    int maxJ, i,j , swapCount = 0;

/* printf("enter insertionSort len=%d\n",len) ; */
//     mexPrintf("enter insertionSort len=%d\n",len);
//     for(int ii=0; ii<len; ii++) {
//         mexPrintf("iSort.arr[%d]=%0.02f\n",ii,arr[ii]);
//     }
    
    if(len < 2) { return 0; }

    maxJ = len - 1;
    for(i = len - 2; i >= 0; --i) {
        double  val = arr[i];
        for(j=i; j < maxJ && arr[j + 1] < val; ++j) {
            arr[j] = arr[j + 1];
        }
//         mexPrintf("val=%0.02f (j-i)=%d arr[j]=%0.02f\n",val,j-i,arr[j]);

        arr[j] = val;
        swapCount += (j - i);
    }

    return swapCount;
}

/*-------------------------------------------------------------------------*/

static int merge(double *from, double *to, int middle, int len)
{
    int bufIndex, leftLen, rightLen , swaps ;
    double *left , *right;

/* printf("enter merge\n") ; */

    bufIndex = 0;
    swaps = 0;

    left = from;
    right = from + middle;
    rightLen = len - middle;
    leftLen = middle;

    while(leftLen && rightLen) {
//         if(right[0] < left[0]) {
        if(right[0] <= left[0]) {
            to[bufIndex] = right[0];
            swaps += leftLen;
            rightLen--;
            right++;
        } else {
            to[bufIndex] = left[0];
            leftLen--;
            left++;
        }
        bufIndex++;
    }

    if(leftLen) {
#pragma omp critical (MEMCPY)
        memcpy(to + bufIndex, left, leftLen * sizeof(double));
    } else if(rightLen) {
#pragma omp critical (MEMCPY)
        memcpy(to + bufIndex, right, rightLen * sizeof(double));
    }

    return swaps;
}

/*-------------------------------------------------------------------------*/
/* Sorts in place, returns the bubble sort distance between the input array
 * and the sorted array.
 */

static int mergeSort(double *x, double *buf, int len)
{
    int swaps , half ;

/* printf("enter mergeSort\n") ; */

    if(len < 10) {
        return insertionSort(x, len);
    }

    swaps = 0;

    if(len < 2) { return 0; }

    half = len / 2;
    swaps += mergeSort(x, buf, half);
    swaps += mergeSort(x + half, buf + half, len - half);
    swaps += merge(x, buf, half, len);

#pragma omp critical (MEMCPY)
    memcpy(x, buf, len * sizeof(double));
    return swaps;
}

/*-------------------------------------------------------------------------*/

static int getMs(double *data, int len)  /* Assumes data is sorted */
{
    int Ms = 0, tieCount = 0 , i ;

/* printf("enter getMs\n") ; */

    for(i = 1; i < len; i++) {
        if(data[i] == data[i-1]) {
            tieCount++;
        } else if(tieCount) {
            Ms += (tieCount * (tieCount + 1)) / 2;
            tieCount = 0;
        }
    }
    if(tieCount) {
        Ms += (tieCount * (tieCount + 1)) / 2;
    }
    return Ms;
}

/*-------------------------------------------------------------------------*/
/* This function calculates the Kendall correlation tau_b.
 * The arrays arr1 should be sorted before this call, and arr2 should be
 * re-ordered in lockstep.  This can be done by calling
 *   qsort_floatfloat(len,arr1,arr2)
 * for example.
 * Note also that arr1 and arr2 will be modified, so if they need to
 * be preserved, do so before calling this function.
 */

int kendallNlogN( double *arr1, double *arr2, int len )
{
    int m1 = 0, m2 = 0, tieCount, swapCount, nPair, s,i ;
//     double cor ;

    if( len < 2 ) return 0 ;

    nPair = len * (len - 1) / 2;
    s = nPair;

    tieCount = 0;
    for(i = 1; i < len; i++) {
        if(arr1[i - 1] == arr1[i]) {
            tieCount++;
        } else if(tieCount > 0) {
            insertionSort(arr2 + i - tieCount - 1, tieCount + 1);
            m1 += tieCount * (tieCount + 1) / 2;
            s += getMs(arr2 + i - tieCount - 1, tieCount + 1);
            tieCount = 0;
        }
    }
    if(tieCount > 0) {
        insertionSort(arr2 + i - tieCount - 1, tieCount + 1);
        m1 += tieCount * (tieCount + 1) / 2;
        s += getMs(arr2 + i - tieCount - 1, tieCount + 1);
    }

//     for(int ii=0; ii<len; ii++) {
//         mexPrintf("arr1[%d]=%0.02f arr2[%d]=%0.02f\n",ii,arr1[ii],ii,arr2[ii]);
//     }
    
    swapCount = mergeSort(arr2, arr1, len);

    m2 = getMs(arr2, len);
//     m2 = 0;
    s -= (m1 + m2) + 2 * swapCount;

    return s ;
}

inline int sgn(float v) {
    return (v > 0) - (v < 0);
}
// #define sgn(v) (v < 0) ? -1 : ((v > 0) ? 1 : 0)

// int kendall_naive( double *arr1, double *arr2, int len )
int kendall_naive( double *arr1, int len )
{
    int K = 0;
    for(int ii=0; ii<len-1; ii++) {
        // Can we use MKL for the inner for-loop?
        for(int jj=ii+1; jj<len; jj++) {
            K += (sgn(arr1[ii]-arr1[jj])*-1);
        }
    }
    return K;
}

/* The gateway function */
void mexFunction( int nlhs, mxArray *plhs[],
                  int nrhs, const mxArray *prhs[])
{
    double multiplier;              /* input scalar */
    double *x;                     /* 1xN input matrix */
    double *y;                     /* 1xN input matrix */
    size_t len;                   /* size of matrix */
    int S;                          /* output value */

    /* check for proper number of arguments */
    if(nrhs!=2) {
        mexErrMsgIdAndTxt("MyToolbox:arrayProduct:nrhs","Two inputs required.");
    }
    if(nlhs!=1) {
        mexErrMsgIdAndTxt("MyToolbox:arrayProduct:nlhs","One output required.");
    }
        
    /* make sure the first input argument is type double array */
    if( !mxIsDouble(prhs[0]) || !mxIsDouble(prhs[1]) ) {
        mexErrMsgIdAndTxt("MyToolbox:arrayProduct:notDouble","Input matrices must be type double.");
    }
    
    /* get the value of the scalar input  */
    multiplier = mxGetScalar(prhs[0]);

    /* create a pointer to the real data in the input matrix  */
    x = mxGetPr(prhs[0]);
    y = mxGetPr(prhs[1]);
    
    /* get dimensions of the input matrix */
    len = mxGetNumberOfElements(prhs[0]);
    
    S = kendall_naive( y, len );
//     S = kendallNlogN( x, y, len );

    /* create the output matrix */
    plhs[0] = mxCreateNumericMatrix(1, 1, mxINT32_CLASS, mxREAL);
    int * data = (int *) mxGetData(plhs[0]);
    data[0] = S;
}
