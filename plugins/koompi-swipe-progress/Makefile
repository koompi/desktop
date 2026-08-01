CXXFLAGS += -shared -fPIC --no-gnu-unique -std=c++26 -Wall -O2
CXXFLAGS += $(shell pkg-config --cflags hyprland pixman-1 libdrm)

all: koompi-swipe-progress.so

koompi-swipe-progress.so: main.cpp
	$(CXX) $(CXXFLAGS) main.cpp -o $@

clean:
	rm -f koompi-swipe-progress.so

.PHONY: all clean
