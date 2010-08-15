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
#include "EthernetDNS.h"

#include "FluidDB.h"

#define USER username here
#define PASS password here

/// MAC address should be unique to the local network
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
/// IPv4 IP address
byte ip[4] = { 172, 20, 1, 24 };
/// Local gateway
byte gateway[4] = { 172, 20, 1, 1 };
/// Netmask
byte subnet[4] = { 255, 255, 255, 0 };

/// DNS
byte dnsServerIp[] = { 172, 20, 1, 1};

/// Delay between readings (sec)
int interval_sec = 10;

FluidDB fdb;

char uid[37];

int happyPin = 8;
int failPin = 7;
int measurePin = 6;

Server server(80);

/** Setup initialises Ethernet system, grabs DNS info,
 *  and looks for the object we're going to update.
 */
void setup(void)
{
  Serial.begin(9600);
  Serial.println("Booting up...");
  
  Ethernet.begin(mac, ip, gateway, subnet);
  pinMode(measurePin, OUTPUT);
  pinMode(failPin, OUTPUT);
  pinMode(happyPin, OUTPUT);
  
  digitalWrite(failPin, HIGH);
  digitalWrite(happyPin, LOW);
  digitalWrite(measurePin, LOW);
  
  delay(3000); // wait for ethernet to start up
  
  EthernetDNS.setDNSServer(dnsServerIp);
  Serial.println("Perform DNS query");
  
  while (!fdb.setServer())
  {
    Serial.println("trying again");
    delay(2000);
  }
  digitalWrite(failPin, LOW);
  
  Serial.println("Resolved.");
  
  if (fdb.login(USER, PASS))
  {
    Serial.println("Set FDB login");
  }
  else
  {
    Serial.println("Login setup failed somehow");
  }
  
  Serial.println("Searching for desired object...");
  char response[100] = "";
  int result = fdb.call("GET", "/objects?query=widget/FFM/device_id=42", 0,
                        0, response, 100);
  Serial.print("Result code is ");
  Serial.println(result, DEC);
  
  bool uid_found = false;
  if (strlen(response) > 36)
  {
    uid_found = true;
  }
      
  // Couldn't get an object to update
  if (!uid_found)
  {
    Serial.println("Could not find desired object!  Aborting");
    while (1)
    {
      delay(500);
      digitalWrite(failPin, LOW);
      delay(500);
      digitalWrite(failPin, HIGH);
    }
  }
  else
  {
    digitalWrite(happyPin, HIGH);
  }

  // Cut out and keep the first UID received from the JSON
  // which had better be of the form { "uid" : ["...
  strncpy(uid, response+10, 36);
  uid[36] = 0; // null terminate
    
  // Start the web server
  server.begin();
}

const int MEASURE_DELAY = 10; // milliseconds

void loop()
{
  // Only turn the measuring pin on for the reading, otherwise
  // we polarise the soil
  digitalWrite(measurePin, HIGH);
  delay(MEASURE_DELAY);
  
  uint32_t raw_val = analogRead(0);
  Serial.print("Raw ADC value is ");
  Serial.print(raw_val);
  digitalWrite(measurePin, LOW);
  
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
  
  
  Serial.print("Updating FluidDB object ");
  Serial.println(uid);
  
  char uri[80];
  snprintf(uri, 80, "/objects/%s/widget/FFM/reading", uid);
  char data[10];
  snprintf(data, 10, "%d", raw_val);
  int res = fdb.call("PUT", uri, FluidDB::SIMPLE_DATA,
                          data);
  Serial.print("Result code is ");
  Serial.println(res, DEC);
  
  // Expected response 204 no content
  if (res == 204)
  {
     Serial.println("Success!");
     digitalWrite(happyPin, HIGH);
     delay(1000);
     digitalWrite(happyPin, LOW);
  }
  else
  {
     digitalWrite(failPin, HIGH);
     delay(1000);
     digitalWrite(failPin, LOW);
  }
  
  // Have a well-earned rest
  for (int i = 0; i < interval_sec * 10; ++i)
  {
    Client client = server.available();
    if (client)
    {
      // an http request ends with a blank line
      boolean current_line_is_blank = true;
      while (client.connected()) 
      {
        if (client.available()) 
        {
          char c = client.read();
          // if we've gotten to the end of the line (received a newline
          // character) and the line is blank, the http request has ended,
          // so we can send a reply
          if (c == '\n' && current_line_is_blank) 
          {
            // send a standard http response header
            //Serial.println("Request received");
            client.println("HTTP/1.0 200 OK");
            client.println("Content-Type: text/html");
            client.println();
            
            client.println("<html><head><title>FluidDB Fluid Monitor</title></head><body>");
            client.print("<p>Current reading is ");
            client.print(raw_val, DEC);
            client.println("</p>");
            if (strlen(uid) > 0)
            {
              client.print("<p>Applying to object '");
              client.print(uid);
              client.println("'</p>");
            }
            else
            {
              client.println("<p>Could not find IDed object to tag</p>");
            }
            client.println("</body></html>");
            
            break;
          }
          if (c == '\n') {
            // we're starting a new line
            current_line_is_blank = true;
          } else if (c != '\r') {
            // we've gotten a character on the current line
            current_line_is_blank = false;
          }
        }
      }
      // give the web browser time to receive the data
      delay(1);
      client.stop();
    }
    else
    {
      delay(100);
    }
  }
}

