#include "SDL.h"

FILE *scene_fd;
int palette[16];

uint16_t getw() {
	return getc(scene_fd) | (getc(scene_fd)<<8);
}

void draw_hline(SDL_Renderer* renderer, int col, int x1, int x2, int y) {
	int r=(col>>3)&0xFF,
		g=(col<<1)&0xFF,
		b=(col<<5)&0xFF;
    SDL_SetRenderDrawColor(renderer, r, g, b, SDL_ALPHA_OPAQUE);
    SDL_RenderDrawLine(renderer, x1, y, x2, y);
}

SDL_bool draw_frame(SDL_Renderer* renderer) {
	flags = getc(scene_fd);

	/* 64kb boundary */
	while(flags == 0x55) flags = getc(scene_fd);

	if(flags == EOF) return SDL_TRUE;

	if(flags & 1) {
		/* clear */
    	SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);
    	SDL_RenderClear(renderer);
	}

	if(flags & 2) {
		/* palette data */
		uint16_t mask = getw();
		for(int i=0; i<16; i++) {
			if(mask & (1<<i) == 0) continue;

			/* reverse order (bit 15 -> palette 0) */
			palette[15-i] = getw();
		}
	}

	if(flags & 4) {
		/* indexed mode */
		uint8_t vert_num = getc(scene_fd);
	} else {
		/* non-indexed mode */
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
        SDL_Renderer* renderer = NULL;

        if (SDL_CreateWindowAndRenderer(255, 200, 0, &window, &renderer) == 0) {
            SDL_bool done = SDL_FALSE;

            while (!done) {
                SDL_Event event;


				done = draw_frame(renderer);
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
