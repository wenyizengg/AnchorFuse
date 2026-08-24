# Copyright (C) 2026 Wenyi Chen

# Compiler and options
CXX = clang++
CXXFLAGS = -Wall -Wextra -g -std=c++17 -pthread

TARGET = main

OBJECTS = \
	main.o \
	connector.o \
	connection_pool.o \
	GPS_anchor_service.o \
	save_anchor_service.o \
	server.o

INCLUDES = \
	-I/opt/homebrew/include \
	-I/opt/homebrew/opt/boost/include \
	-I/opt/homebrew/opt/libpq/include

LIBS = \
	-L/opt/homebrew/lib \
	-L/opt/homebrew/opt/libpq/lib \
	-lpqxx \
	-lpq \
	-Wl,-rpath,/opt/homebrew/lib \
	-Wl,-rpath,/opt/homebrew/opt/libpq/lib

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJECTS) $(LIBS)

main.o: main.cpp server.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c main.cpp

connector.o: connector.cpp connector.h connection_pool.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c connector.cpp

connection_pool.o: connection_pool.cpp connection_pool.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c connection_pool.cpp

GPS_anchor_service.o: GPS_anchor_service.cpp GPS_anchor_service.h connector.h connection_pool.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c GPS_anchor_service.cpp

save_anchor_service.o: save_anchor_service.cpp save_anchor_service.h connector.h connection_pool.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c save_anchor_service.cpp

server.o: server.cpp server.h GPS_anchor_service.h save_anchor_service.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c server.cpp

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all clean

