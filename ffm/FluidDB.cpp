
#include <string.h>

#include "FluidDB.h"

#include "EthernetDNS.h"

const char FluidDB::MAIN[] = "fluiddb.fluidinfo.com";
const char FluidDB::SANDBOX[] = "sandbox.fluidinfo.com";

const char FluidDB::SIMPLE_DATA[] = "application/vnd.fluiddb.value+json";

FluidDB::FluidDB(void) :
  server(MAIN),
  server_ip(),
  login_details(),
  socket(server_ip, HTTP),
  current_status(NoServerIp)
{
}

bool FluidDB::setServer(const char* _server)
{
  DNSError err = EthernetDNS.resolveHostName(server, server_ip);
    
  if (err == DNSSuccess)
  {
    current_status = NoLogin;
    return true;
  }
  
  return false;
}

bool FluidDB::setServer(const uint8_t* _ip)
{
  memcpy(server_ip, _ip, sizeof(server_ip));
  current_status = NoLogin;
  return true;
}


int FluidDB::call(const char* method, const char* uri, const char* mime,
                  const char* payload, char* response, size_t response_size)
{
  int ret = 0;
  if (!socket.connect())
  {
    return 0;
  }
  
  // First line
  socket.print(method);
  socket.print(" ");
  socket.print(uri);
  socket.println(" HTTP/1.0");
  
  
  // Add basic auth
  socket.print("Authorization: Basic ");
  socket.println(login_details);
  
  if (payload != 0)
  {
    socket.print("Content-Type: ");
    socket.println(mime);
    socket.print("Content-Length: ");
    socket.println(strlen(payload));
  }
  
  // end of headers
  socket.println();
  
  if (payload != 0)
  {
    // No new line, the content length has been sent ahead.
    socket.print(payload);
  }
  
  // Now we await a response
  const size_t RESPONSE_BUFFER_SIZE = 100;
  char resp_buffer[RESPONSE_BUFFER_SIZE];
  int idx = 0;
  bool buffer_full = false;
  
  // Response is received here, char by char.  This is
  // written into a line-by-line buffer.  When the HTTP
  // return code appears, it is checked to be a 20x success
  // response
  
  // Buffer overflow is also avoided in case tonnes of JSON
  // is returned, as we can't parse it.
  while (socket.connected() && !buffer_full)
  {
    if (socket.available()) 
    {
      resp_buffer[idx] = socket.read();
      idx++;
      
      if (idx >= RESPONSE_BUFFER_SIZE)
      {
          buffer_full = true;
      }
      else if (resp_buffer[idx-1] == '\n')
      {
        resp_buffer[idx] = 0;
        //Serial.println(response);
        idx = 0;
        
        if (!strncmp(resp_buffer, "HTTP/1.0", 8))
        {
          if (!sscanf(resp_buffer+9, "%d", &ret))
          {
            // Couldn't read HTTP status
            ret = 0;
          }
        }
      }
    }
  }
  
  socket.stop();
  resp_buffer[idx] = 0;
    
  if (buffer_full)
  {
    return -1;
  }
  
  if ((response_size > 0) && response)
  {
    strncpy(response, resp_buffer, response_size); // response_size can be smaller idx
  }
  
  return ret;
}

bool FluidDB::login(const char* user, const char* pass)
{
  bool ret = false;
  char login_input[40];
  if (snprintf(login_input, 40, "%s:%s", user, pass) < 40)
  {
    ret = mimeEncode(login_input, login_details);
  }
  
  if (ret)
  {
    current_status = Success;
  }

  return ret;  
}

/** Convert 6 bit number to ASCII character.
 *  \param c valid 0-63
 *  \returns Base64 representation.
 */
char FluidDB::mime_code(const char c)
{
    if (c < 26)
    {
        return c+'A';
    }
    else if (c < 52)
    {
        return c-26+'a';
    }
    else if (c < 62)
    {
        return c-52+'0';
    }
    else if (c == 62) 
    {
        return '+';
    }
    return '/';
}

/** Performs Base64 encoding of a string, to an output.
 *  Output length is limited to 64 characters.
 */
bool FluidDB::mimeEncode(const char *in, char* out)
{
    bool ret = false;
    int i = 0, j = 0, c[3];
    while (j < 64 && in[i]) 
    {
        c[0] = in[i++];
        c[1] = in[i] ? in[i++] : 0;
        c[2] = in[i] ? in[i++] : 0;
        out[j++] = mime_code(c[0]>>2);
        out[j++] = mime_code(((c[0]<<4)&0x30) | (c[1]>>4));
        out[j++] = c[1] ? mime_code(((c[1]<<2)&0x3c) | (c[2]>>6)) : '=';
        out[j++] = c[2] ? mime_code(c[2]&0x3f) : '=';
    }
    if (j < 64)
    {
        ret = true;
    }
    out[j] = 0;
    return ret;
}
