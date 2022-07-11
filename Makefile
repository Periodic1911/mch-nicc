SDLFLAGS := $(shell sdl2-config --cflags --libs)

all: sdl

sdl: sdl.c
	gcc $(SDLFLAGS) -o sdl sdl.c

clean:
	rm sdl
