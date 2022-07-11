#include <stdint.h>
#include <stdarg.h>
/* draw_poly return codes */
enum {POLY_MORE, POLY_FRAME, POLY_FRAME64, POLY_STREAM};

FILE *scene_fd;
int palette[16];
SDL_Renderer* renderer = NULL;

uint16_t get16() {
	return (getc(scene_fd)<<8) | getc(scene_fd);
}

void draw_hline(int col, int x1, int x2, int y) {
	int r=(col>>3)&0xFF,
		g=(col<<1)&0xFF,
		b=(col<<5)&0xFF;
    SDL_SetRenderDrawColor(renderer, r, g, b, SDL_ALPHA_OPAQUE);
    SDL_RenderDrawLine(renderer, x1, y, x2, y);
}

void fill_poly(uint8_t col, uint8_t polynum, uint8_t *px, uint8_t *py) {
	uint8_t ymin,ymax;
	ymin = py[0];
	ymax = py[0];

	for(int i=0; i<polynum; i++) {
		if(py[i] < ymin) ymin = py[i];
		if(py[i] > ymax) ymax = py[i];
	}
	if(ymin < 0) ymin = 0;
	if(ymax > 200) ymax = 200;

	uint8_t nodeX[16];
	uint8_t nodes = 0;
	uint8_t j=polynum-1;

	for(int y=ymin; y<ymax; y++) {
		uint8_t i;
		nodes = 0;

		/* Find intersection nodes */
		for(i=0; i<polynum; i++) {
			if(py[i]<y && py[j]>=y ||
			   py[j]<y && py[i]>=y) {
				nodeX[nodes++] = px[i]+(y-py[i])*(px[j]-px[i])/(py[j]-py[i]);
			}
			j=i;
		}

		i=0;
	
		/* Sort nodes with bubble sort */
		while(i<nodes-1) {
			if(nodeX[i]>nodeX[i+1]) {
				uint8_t swap;
				swap = nodeX[i];
				nodeX[i] = nodeX[i+1];
				nodeX[i+1] = swap;
				if(i>0) i--;
			} else {
				i++;
			}
		}
	
		/* fill pixels between node pairs */
		for(i=0; i<nodes; i+=2) {
			draw_hline(palette[col],nodeX[i],nodeX[i+1],y);
		}
	}
}

int draw_poly(uint8_t *vertx_a, uint8_t *verty_a) {
	int indexed_mode = (vertx_a != NULL);
	uint8_t poly_desc = getc(scene_fd);

	if(poly_desc == 0xFF) return POLY_FRAME;
	if(poly_desc == 0xFE) return POLY_FRAME64;
	if(poly_desc == 0xFD) return POLY_STREAM;

	uint8_t col,polynum;
	col = poly_desc >> 4;
	polynum = poly_desc & 0x0F;

	uint8_t px[16];
	uint8_t py[16];

	if(indexed_mode) {
		for(int i=0; i<polynum; i++) {
			uint8_t vertid = getc(scene_fd);
			px[i] = vertx_a[vertid];
			py[i] = verty_a[vertid];
		}
		fill_poly(col,polynum,px,py);
	} else {
		/* non-indexed mode */
		for(int i=0; i<polynum; i++) {
			px[i] = getc(scene_fd);
			py[i] = getc(scene_fd);
		}
		fill_poly(col,polynum,px,py);
	}


	return POLY_MORE;
}

SDL_bool draw_frame() {
	uint8_t flags = getc(scene_fd);

	if(flags == EOF) return SDL_TRUE;

	if(flags & 1) {
		/* clear */
    	SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);
    	SDL_RenderClear(renderer);
	}

	if(flags & 2) {
		/* palette data */
		uint16_t mask = get16();
		for(int i=0; i<16; i++) {
			if((mask & (1<<i)) == 0) continue;

			/* reverse order (bit 15 -> palette 0) */
			palette[15-i] = get16();
		}
	}

	int ret;
	if(flags & 4) {
		/* indexed mode */
		uint8_t vert_num = getc(scene_fd);
		uint8_t vertx[256];
		uint8_t verty[256];
		for(int i=0; i<vert_num; i++) {
			vertx[i] = getc(scene_fd);
			verty[i] = getc(scene_fd);
		}

		do {
			ret = draw_poly(vertx,verty);
		} while(ret == POLY_MORE);

	} else {
		/* non-indexed mode */
		do {
			ret = draw_poly(NULL,NULL);
		} while(ret == POLY_MORE);
	}

	/* 64kB boundary */
	if(ret == POLY_FRAME64) {
		long pos = ftell(scene_fd);
		pos = ((pos>>16)+1)<<16;
		fseek(scene_fd, pos, SEEK_SET);
	}

	/* stream over */
	if(ret == POLY_STREAM) {
		return SDL_TRUE;
	}

	return SDL_FALSE;
}

int main(int argc, char* argv[])
{
	if(argc !=2 ) {
		printf("Usage: %s [scene binary]\n",argv[0]);
		return 1;
	}

	scene_fd = fopen(argv[1],"r");
	if(scene_fd == NULL) {
		printf("File %s not found\n",argv[1]);
		return 1;
	}


    if (SDL_Init(SDL_INIT_VIDEO) == 0) {
        SDL_Window* window = NULL;

        if (SDL_CreateWindowAndRenderer(255, 200, 0, &window, &renderer) == 0) {
            SDL_bool done = SDL_FALSE;

            while (!done) {
                SDL_Event event;


				done = draw_frame();
                SDL_RenderPresent(renderer);

				SDL_Delay(16);
                if (SDL_PollEvent(&event)) {
                    if (event.type == SDL_QUIT) {
                        done = SDL_TRUE;
                    }
                }
            }
        }

        if (renderer) {
            SDL_DestroyRenderer(renderer);
        }
        if (window) {
            SDL_DestroyWindow(window);
        }
    }
    SDL_Quit();
    return 0;
}
