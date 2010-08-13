/*
Copyright (c) 2010 Stephen Bridges & Nicholas Tollervey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
 */

/**
 *  \file
 *  Proof of concept code for connecting an Arduino with Ethernet Shield
 *  to a FluidDB server.
 *  
 *  This connects to FluidDB and searches for an object tagged with
 *  widget/FFM/device_id set to a value of 42, which represents the plant
 *  being monitored within FluidDB.  It then tags this object with the
 *  moisture reading of the plant pot.
 *
 *  \section Requirements
 *  The extended Arduino Ethernet library is needed for DNS lookups.
 *  Define \c NEED_DNS.
 */

#include "Ethernet.h"

#ifdef NEED_DNS
#include "EthernetDNS.h"
#endif

/// MAC address should be unique to the local network
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
/// IPv4 IP address
byte ip[4] = { 192, 168, 1, 2 };
/// Local gateway
byte gateway[4] = { 192, 168, 1, 1 };
/// Netmask
byte subnet[4] = { 255, 255, 255, 0 };

#ifdef NEED_DNS
/// DNS
byte dnsServerIp[] = { 192, 168, 1, 1};

#define FLUID_DOMAIN "fluiddb.fluidinfo.com"
#endif

const int UPDATE_DELAY_MS = 10000; // 10 seconds

/// Fluid's IP address to contact (check this if not using DNS!)
static uint8_t server[] = {174, 129, 210, 19};

Client client(server, 80);

/** Convert 6 bit number to ASCII character.
 *  \param c valid 0-63
 *  \returns Base64 representation.
 */
static char mime_code(const char c)
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

/// This is the format required for HTTP Basic authentication
/// with a colon separator
char user_pass[] = "USERNAME:PASSWORD";
char output[65];

/** Performs Base64 encoding of a string, to an output.
 *  Output length is limited to 64 characters.
 */
bool mimeEncode(const char *in, char* out)
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

void setup(void)
{
    Serial.begin(9600);
    Serial.println("Booting up...");
    mimeEncode(user_pass, output);
    
    Ethernet.begin(mac, ip, gateway, subnet);
    
    pinMode(8, OUTPUT);
    digitalWrite(8, LOW);
    
    delay(3000); // wait for ethernet to start up
    
#ifdef NEED_DNS
    Serial.println("Perform DNS query");
    
    EthernetDNS.setDNSServer(dnsServerIp);
    DNSError err = EthernetDNS.resolveHostName(FLUID_DOMAIN, server);
    bool tried = false;
    do
    {
        // Repeat until DNS query resolves
        if (tried)
        {
            Serial.println("Could not resolve " FLUID_DOMAIN);
            delay(2000);
        }
        err = EthernetDNS.resolveHostName(FLUID_DOMAIN, server);
        tried = true;
    }
    while (err != DNSSuccess);
    
    Serial.println("Resolved " FLUID_DOMAIN);
#endif // NEED_DNS
}

void loop()
{
    uint32_t raw_val = analogRead(0);
    Serial.print("Raw ADC value is ");
    Serial.print(raw_val);
    
    // Mangle value to represent a percentage of 0/100 between
    // a minimum and maximum
    const uint32_t min_val = 350, max_val = 750;
    
    // Lower bound
    raw_val = (raw_val < min_val) ? min_val : raw_val;
    // Upper bound
    raw_val = (raw_val > max_val) ? max_val : raw_val;
    
    raw_val -= min_val; // Remove lower bound
    raw_val *= 100;
    raw_val /= (max_val - min_val); // Convert to percentage, no floating point used
    Serial.print(" converted to ");
    Serial.print(raw_val);
    Serial.print("%\r\n");
    
    Serial.println("Searching for desired object...");
    if (client.connect()) 
    {
        // HTTP request
        digitalWrite(8, HIGH);
        
        // Request object ID for objects tagged with widget/FFM/device_id
        // set to 42
        client.println("GET /objects?query=widget/FFM/device_id=42 HTTP/1.0");
        // Add basic auth
	client.print("Authorization: Basic ");
	client.println(output);
        client.println();
    } 
    else
    {
        Serial.println("connection failed");
    }
    
    const size_t RESPONSE_BUFFER_SIZE = 300;
    char response[RESPONSE_BUFFER_SIZE];
    int idx = 0;
    char uid[37];
    bool buffer_full = false;
    bool uid_found = false;
    
    // Response is received here, char by char.  This is
    // written into a line-by-line buffer.  When the HTTP
    // return code appears, it is checked to be a 20x success
    // response
    
    // Buffer overflow is also avoided in case tonnes of JSON
    // is returned, as we can't parse it.
    while (client.connected() && !buffer_full)
    {
        if (client.available()) 
        {
            response[idx] = client.read();
            idx++;
            
            if (idx >= RESPONSE_BUFFER_SIZE)
            {
                buffer_full = true;
            }
            else if (response[idx-1] == '\n')
            {
                response[idx] = 0;
                //Serial.println(response);
                idx = 0;
                
                if (!strncmp(response, "HTTP/1.0", 8))
                {
                    if (!strncmp(response+9, "20", 2))
                    {
                        Serial.println("Analysis: Success!");
                        uid_found = true;
                    }
                    else
                    {
                        Serial.print(response);
                        digitalWrite(8, LOW);
                    }
                }
            }
        }
    }
    
    // Couldn't get an object to update
    if (!uid_found)
    {
        Serial.println("Could not find desired object!  Aborting");
        delay(30000);
        return;
    }

    // Cut out and keep the first UID received from the JSON
    // which had better be of the form { "uid" : ["...
    response[idx] = 0;
    strncpy(uid, response+10, 36);
    uid[36] = 0; // null terminate
    
    client.stop();
    Serial.println("disconnecting.");
    
    
    Serial.print("Updating FluidDB object ");
    Serial.println(uid);
    if (client.connect()) 
    {
        // HTTP headers need authorisation again as this is a new
        // connection, and also the length and encoding of our
        // payload.
        char call[100];
        snprintf(call, 100, "PUT /objects/%s/widget/FFM/reading HTTP/1.0", uid);
        client.println(call);
	client.print("Authorization: Basic ");
	client.println(output);
        client.println("Content-Type: application/vnd.fluiddb.value+json");
        client.print("Content-Length: ");
        client.println(snprintf(call, 10, "%d", raw_val));
        client.println();
        client.print(call);
    }
    
    // Print out FluidDB's response (expecting 204 No Content)
    // TODO: check.
    while (client.connected())
    {
        if (client.available()) 
        {
            char c = client.read();
            Serial.print(c);
        }
    }
    Serial.println("disconnecting.");
    client.stop();
    
    // Have a well-earned rest
    delay(UPDATE_DELAY_MS);
}
