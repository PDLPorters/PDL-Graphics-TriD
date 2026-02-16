/*
 * Copyright (c) 1999-2000 by Pawel W. Olszta
 * Written by Pawel W. Olszta, <olszta@sourceforge.net>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Sotware.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * PAWEL W. OLSZTA BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stddef.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>


/*
 * Compute lookup table of cos and sin values forming a circle
 * (or half circle if halfCircle==TRUE)
 *
 * Notes:
 *    It is the responsibility of the caller to free these tables
 *    The size of the table is (n+1) to form a connected loop
 *    The last entry is exactly the same as the first
 *    The sign of n can be flipped to get the reverse loop
 */
static char *fghCircleTable(float **sint, float **cost, const int n, const char halfCircle)
{
    int i;

    /* Table size, the sign of n flips the circle direction */
    const int size = abs(n);

    /* Determine the angle between samples */
    const float angle = (halfCircle?1:2)*(float)M_PI/(float)( ( n == 0 ) ? 1 : n );

    /* Allocate memory for n samples, plus duplicate of first entry at the end */
    *sint = malloc(sizeof(float) * (size+1));
    *cost = malloc(sizeof(float) * (size+1));

    if (!(*sint) || !(*cost))
    {
        free(*sint);
        free(*cost);
        return "Failed to allocate memory in fghCircleTable";
    }

    /* Compute cos and sin around the circle */
    (*sint)[0] = 0.0;
    (*cost)[0] = 1.0;

    for (i=1; i<size; i++)
    {
        (*sint)[i] = (float)sin(angle*i);
        (*cost)[i] = (float)cos(angle*i);
    }


    if (halfCircle)
    {
        (*sint)[size] =  0.0f;  /* sin PI */
        (*cost)[size] = -1.0f;  /* cos PI */
    }
    else
    {
        /* Last sample is duplicate of the first (sin or cos of 2 PI) */
        (*sint)[size] = (*sint)[0];
        (*cost)[size] = (*cost)[0];
    }
    return NULL;
}

int calc_nVert(int slices, int stacks) {
    /* number of unique vertices */
    if (slices==0 || stacks<2)
    {
        /* nothing to generate */
        return 0;
    }
    return slices*(stacks-1)+2;
}

char *fghGenerateSphere(float radius, int slices, int stacks, float *vertices, float *normals, int nVert)
{
    int i,j;
    int idx = 0;    /* idx into vertex/normal buffer */
    float x,y,z;

    /* Pre-computed circle */
    float *sint1,*cost1;
    float *sint2,*cost2;

    if (nVert == 0)
    {
        /* nothing to generate */
        return NULL;
    }

    /* precompute values on unit circle */
    char *err = fghCircleTable(&sint1,&cost1,-slices,0);
    if (err) return err;
    err = fghCircleTable(&sint2,&cost2, stacks,1);
    if (err) return err;

    /* top */
    vertices[0] = 0.f;
    vertices[1] = 0.f;
    vertices[2] = radius;
    normals [0] = 0.f;
    normals [1] = 0.f;
    normals [2] = 1.f;
    idx = 3;

    /* each stack */
    for( i=1; i<stacks; i++ )
    {
        for(j=0; j<slices; j++, idx+=3)
        {
            x = cost1[j]*sint2[i];
            y = sint1[j]*sint2[i];
            z = cost2[i];

            vertices[idx  ] = x*radius;
            vertices[idx+1] = y*radius;
            vertices[idx+2] = z*radius;
            normals [idx  ] = x;
            normals [idx+1] = y;
            normals [idx+2] = z;
        }
    }

    /* bottom */
    vertices[idx  ] =  0.f;
    vertices[idx+1] =  0.f;
    vertices[idx+2] = -radius;
    normals [idx  ] =  0.f;
    normals [idx+1] =  0.f;
    normals [idx+2] = -1.f;

    /* Done creating vertices, release sin and cos tables */
    free(sint1);
    free(cost1);
    free(sint2);
    free(cost2);
    return NULL;
}

void calc_strip_idx(uint32_t  *stripIdx, int slices, int stacks, int nVert) {
  int i,j,idx;
  uint32_t offset;
  /* top stack */
  for (j=0, idx=0;  j<slices;  j++, idx+=2)
  {
    stripIdx[idx  ] = j+1;              /* 0 is top vertex, 1 is first for first stack */
    stripIdx[idx+1] = 0;
  }
  stripIdx[idx  ] = 1;                    /* repeat first slice's idx for closing off shape */
  stripIdx[idx+1] = 0;
  idx+=2;
  /* middle stacks: */
  /* Strip indices are relative to first index belonging to strip, NOT relative to first vertex/normal pair in array */
  for (i=0; i<stacks-2; i++, idx+=2)
  {
    offset = 1+i*slices;                    /* triangle_strip indices start at 1 (0 is top vertex), and we advance one stack down as we go along */
    for (j=0; j<slices; j++, idx+=2)
    {
      stripIdx[idx  ] = offset+j+slices;
      stripIdx[idx+1] = offset+j;
    }
    stripIdx[idx  ] = offset+slices;        /* repeat first slice's idx for closing off shape */
    stripIdx[idx+1] = offset;
  }
  /* bottom stack */
  offset = 1+(stacks-2)*slices;               /* triangle_strip indices start at 1 (0 is top vertex), and we advance one stack down as we go along */
  for (j=0; j<slices; j++, idx+=2)
  {
    stripIdx[idx  ] = nVert-1;              /* zero based index, last element in array (bottom vertex)... */
    stripIdx[idx+1] = offset+j;
  }
  stripIdx[idx  ] = nVert-1;                  /* repeat first slice's idx for closing off shape */
  stripIdx[idx+1] = offset;
}

int calc_numVertIdxsPerPart(int slices) {
  return (slices+1)*2;
}
