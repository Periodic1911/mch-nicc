#include "SDL.h"

void draw_hline(SDL_Renderer* renderer, int col, int x1, int x2, int y) {
	int r=(col>>3)&0xFF,
		g=(col<<1)&0xFF,
		b=(col<<5)&0xFF;
    SDL_SetRenderDrawColor(renderer, r, g, b, SDL_ALPHA_OPAQUE);
    SDL_RenderDrawLine(renderer, x1, y, x2, y);
}

SDL_bool draw_frame(SDL_Renderer* renderer) {
	/* clear */
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);
    SDL_RenderClear(renderer);

	for(int i=0; i<200; i++) {
		draw_hline(renderer, i*4, 0, 255, i);
	}

	return SDL_FALSE;
}

int main(int argc, char* argv[])
{
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
