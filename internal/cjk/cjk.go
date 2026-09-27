package cjk

/*
#cgo CFLAGS: -DSQLITE_CORE
#include "sqlite3-binding.h"
int sqlite3_cjk_init(sqlite3*, char**, const sqlite3_api_routines*);
static int reg(void){ return sqlite3_auto_extension((void(*)(void))sqlite3_cjk_init); }
*/
import "C"

func init() { C.reg() }
