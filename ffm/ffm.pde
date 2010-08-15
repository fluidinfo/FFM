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

const int UPDATE_DELAY_MS = 20000; // 10 seconds

FluidDB fdb;

char uid[37];
    
void setup(void)
{
    Serial.begin(9600);
    Serial.println("Booting up...");
    
    Ethernet.begin(mac, ip, gateway, subnet);
    pinMode(6, OUTPUT);
    pinMode(7, OUTPUT);
    pinMode(8, OUTPUT);
    digitalWrite(6, HIGH);
    digitalWrite(7, LOW);
    digitalWrite(8, LOW);
    
    delay(3000); // wait for ethernet to start up
    
    EthernetDNS.setDNSServer(dnsServerIp);
    Serial.println("Perform DNS query");
    
    while (!fdb.setServer())
    {
        Serial.println("trying again");
        delay(2000);
    }
    digitalWrite(6, LOW);
    
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
        delay(10000);
        return;
    }
    else
    {
      digitalWrite(7, HIGH);
    }

    // Cut out and keep the first UID received from the JSON
    // which had better be of the form { "uid" : ["...
    strncpy(uid, response+10, 36);
    uid[36] = 0; // null terminate
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
    // Print out FluidDB's response (expecting 204 No Content)
    // TODO: check.
    if (res == 204)
    {
       Serial.println("Success!");
       digitalWrite(7, HIGH);
       delay(1000);
       digitalWrite(7, LOW);
    }
    else
    {
       digitalWrite(6, HIGH);
       delay(1000);
       digitalWrite(6, LOW);
    }
    
    // Have a well-earned rest
    delay(UPDATE_DELAY_MS);
}

