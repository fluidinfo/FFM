
#ifndef _FLUIDDB_H
#define _FLUIDDB_H

#include "Ethernet.h"

#include <inttypes.h>

class FluidDB
{
public:
  static const char MAIN[];
  static const char SANDBOX[];
  
  static const char SIMPLE_DATA[];
  
  enum Status
  {
    NoServerIp,
    NoLogin,
    Failure,
    Success
  };
  
  FluidDB(void);
  ~FluidDB(void) {};
  bool setServer(const uint8_t* _ip);
  bool setServer(const char* _server = MAIN);
  
  bool login(const char* user, const char* pass);
  int call(const char* method, const char* uri, const char* mime = 0, 
           const char* payload = 0, char* response = 0, size_t response_size = 0);
  
private:
  const char* server;
  uint8_t server_ip[4];
  char login_details[64];
  Client socket;
  Status current_status;
  
  static char mime_code(const char c);
  bool mimeEncode(const char *in, char* out);
  
  static const int HTTP = 80;
};

#endif // _FLUIDDB_H

// EOF

