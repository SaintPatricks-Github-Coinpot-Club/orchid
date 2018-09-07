//
//  tun_api.h
//  Orchid macOS
//
//  Created by Gregory Hazel on 7/31/18.
//  Copyright © 2018 Example. All rights reserved.
//

#ifndef tun_api_h
#define tun_api_h

#include "orchid.h"
#include <stdio.h>

typedef void (^connection_complete_cb)(int error);
void tun_api_tcp_connect(sockaddr_storage *ss, connection_complete_cb cb);
bool tun_api_udp_packet(ip *p, size_t length);

#endif /* tun_api_h */
