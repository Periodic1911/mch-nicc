// -----------------------------------------------------------------------------
//   Now go on with C
// -----------------------------------------------------------------------------

#include <stdint.h>
#include <stdarg.h>

// -----------------------------------------------------------------------------
//   Timing
// -----------------------------------------------------------------------------

#define CYCLES_US    12
#define CYCLES_MS 12000

uint32_t cycles(void)
{
  uint32_t ticks;
  asm volatile ("rdcycle %0" : "=r"(ticks));
  return ticks;
}

void delay_cycles(uint32_t time)
{
  uint32_t now = cycles();
  while ( (cycles() - now) < time ) {};
}

void us(uint32_t time)
{
  delay_cycles(time * CYCLES_US); // For 48 MHz clock frequency
}

void ms(uint32_t time)
{
  delay_cycles(time * CYCLES_MS); // For 48 MHz clock frequency
}

// -----------------------------------------------------------------------------
//   Terminal IO
// -----------------------------------------------------------------------------

#define UART_DATA  *(volatile uint8_t  *) 0x40010000
#define UART_FLAGS *(volatile uint32_t *) 0x40020000

uint32_t keypressed(void)
{
  return 0x100 & UART_FLAGS ? -1 : 0;
}

uint8_t getchar(void)
{
  while ( 0x100 & ~UART_FLAGS) {};
  return UART_DATA;
}

void serial_putchar(uint8_t character)
{
  while ( 0x200 & UART_FLAGS) {};
  UART_DATA = character;
}

// -----------------------------------------------------------------------------
//   Random numbers
// -----------------------------------------------------------------------------

uint32_t randombit(void)
{
  delay_cycles(100);
  return 0x400 & UART_FLAGS ? 1 : 0;
}

uint32_t random(void)
{
  uint32_t randombits = 0;
  for (uint32_t i = 0; i < 32; i++)
  {
    randombits = randombits << 1 | randombit();
  }
  return randombits;
}

// -----------------------------------------------------------------------------
//   LEDs & Buttons
// -----------------------------------------------------------------------------

#define BUTTONS   *(volatile uint32_t  *) 0x40000080
#define LEDS      *(volatile uint32_t  *) 0x40000100

#define LED_RED   *(volatile uint16_t  *) 0x40000200
#define LED_GREEN *(volatile uint16_t  *) 0x40000400
#define LED_BLUE  *(volatile uint16_t  *) 0x40000800

#define BG_COLOR  *(volatile uint32_t  *) 0x40004000

// -----------------------------------------------------------------------------
//   Output characters both to LCD and serial terminal
// -----------------------------------------------------------------------------

void putchar(uint8_t character)
{
  serial_putchar(character);
}

// -----------------------------------------------------------------------------
//   Pretty printing
// -----------------------------------------------------------------------------

void print_string(const char* s) {
   for(const char* p = s; *p; ++p) {
      putchar(*p);
   }
}

int puts(const char* s) {
   print_string(s);
   putchar('\n');
   return 1;
}

void print_dec(int val) {
   char buffer[255];
   char *p = buffer;
   if(val < 0) {
      putchar('-');
      print_dec(-val);
      return;
   }
   while (val || p == buffer) {
      *(p++) = val % 10;
      val = val / 10;
   }
   while (p != buffer) {
      putchar('0' + *(--p));
   }
}

void print_hex_digits(unsigned int val, int nbdigits) {
   for (int i = (4*nbdigits)-4; i >= 0; i -= 4) {
      putchar("0123456789ABCDEF"[(val >> i) % 16]);
   }
}

void print_hex(unsigned int val) {
   print_hex_digits(val, 8);
}

// -----------------------------------------------------------------------------
//   Formated printing
// -----------------------------------------------------------------------------

int printf(const char *fmt,...)
{
    va_list ap;

    for(va_start(ap, fmt);*fmt;fmt++)
    {
        if(*fmt=='%')
        {
            fmt++;
                 if(*fmt=='s') print_string(va_arg(ap,char *));
            else if(*fmt=='x') print_hex(va_arg(ap,int));
            else if(*fmt=='d') print_dec(va_arg(ap,int));
            else if(*fmt=='c') putchar(va_arg(ap,int));
            else putchar(*fmt);
        }
        else putchar(*fmt);
    }

    va_end(ap);

    return 0;
}

// -----------------------------------------------------------------------------
//   File
// -----------------------------------------------------------------------------
#define FILE_ID  *(volatile uint32_t  *) 0x40100000
#define FILE_MAP *(volatile uint8_t   *) 0x90000000

unsigned int file_offset;

char getc() {
	return *(&FILE_MAP+(file_offset++));
}

uint16_t get16() {
	return (getc()<<8) | getc();
}



// -----------------------------------------------------------------------------
//   Drawing
// -----------------------------------------------------------------------------

volatile uint8_t   *bitmap  = (volatile uint8_t *)  0x10000000
volatile uint16_t  *palette = (volatile uint16_t *) 0x20000000

/* draw_poly return codes */
enum {POLY_MORE, POLY_FRAME, POLY_FRAME64, POLY_STREAM};

void draw_hline(uint8_t col, int x1, int x2, int y) {
	for(int i=x1; i<x2; i++) {
		bitmap[256*y+i] = col;
	}
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
			draw_hline(col,nodeX[i],nodeX[i+1],y);
		}
	}
}

int draw_poly(uint8_t *vertx_a, uint8_t *verty_a) {
	int indexed_mode = (vertx_a != 0);
	uint8_t poly_desc = getc();

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
			uint8_t vertid = getc();
			px[i] = vertx_a[vertid];
			py[i] = verty_a[vertid];
		}
		fill_poly(col,polynum,px,py);
	} else {
		/* non-indexed mode */
		for(int i=0; i<polynum; i++) {
			px[i] = getc();
			py[i] = getc();
		}
		fill_poly(col,polynum,px,py);
	}


	return POLY_MORE;
}

int draw_frame() {
	uint8_t flags = getc();

	if(flags & 1) {
		/* clear */
	}

	if(flags & 2) {
		/* palette data */
		uint16_t mask = get16();
		for(int i=0; i<16; i++) {
			if((mask & (1<<i)) == 0) continue;

			uint16_t pal = get16();
			uint8_t r,g,b;
	        r=(pal>>8)&0x7,
		    g=(pal>>4)&0x7,
		    b=(pal   )&0x7;

			/* reverse order (bit 15 -> palette 0) */
			palette[15-i] = (r<<12|g<<8|b<<2);
		}
	}

	int ret;
	if(flags & 4) {
		/* indexed mode */
		uint8_t vert_num = getc();
		uint8_t vertx[256];
		uint8_t verty[256];
		for(int i=0; i<vert_num; i++) {
			vertx[i] = getc();
			verty[i] = getc();
		}

		do {
			ret = draw_poly(vertx,verty);
		} while(ret == POLY_MORE);

	} else {
		/* non-indexed mode */
		do {
			ret = draw_poly(0,0);
		} while(ret == POLY_MORE);
	}

	/* 64kB boundary */
	if(ret == POLY_FRAME64) {
		file_offset = ((file_offset>>16)+1)<<16;
	}

	/* stream over */
	if(ret == POLY_STREAM) {
		return 1;
	}

	return 0;
}

// -----------------------------------------------------------------------------
//   Main
// -----------------------------------------------------------------------------

int main(int argc, char* argv[])
{
	file_offset = 0;
	FILE_ID = 0xBEEFD00D;
	int done = 0;
	int i=0;

	puts("MCH_NICC");
    while (!done) {
    	if(LED_BLUE) LED_BLUE = 0;
		else LED_BLUE = ( 0x1f) << 11;
		done = draw_frame();
		printf("%d\n",i++);
    }
    LED_BLUE  = 0;
    LED_RED   = ( 0x1f) << 11;
	while(1);
}
