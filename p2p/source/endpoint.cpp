/* Orchid - WebRTC P2P VPN Market (on Ethereum)
 * Copyright (C) 2017-2020  The Orchid Authors
*/

/* GNU Affero General Public License, Version 3 {{{ */
/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.

 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
**/
/* }}} */


#include "endpoint.hpp"

namespace orc {

task<Json::Value> Endpoint::operator ()(const std::string &method, Argument args) const { orc_block({
    const auto body(Unparse([&]() {
        Json::Value root;
        root["jsonrpc"] = "2.0";
        root["method"] = method;
        // xDAI eth_gasPrice used to have a bug that required the id be an integer;
        // but now, Cloudflare has a bug that requires the id be a non-empty string
        root["id"] = "0";
        root["params"] = std::move(args);
        return root;
    }()));

    const auto data(Parse((co_await base_->Fetch("POST", locator_, {
        {"content-type", "application/json"},
        // XXX: move this to a field (maybe optional?) on Endpoint
        {"origin", "https://account.orchid.com"},
    }, body)).ok()));

    if (false)
        Log() << "JSON/RPC " << locator_ << " " << body << " " << Unparse(data) << std::endl;

    orc_assert(data["jsonrpc"] == "2.0");

    const auto error(data["error"]);
    if (!error.isNull())
        orc_throw(Unparse(error));

    const auto id(data["id"]);
    orc_assert_(!id.isNull(), "missing id in " << data);
    orc_assert(id == "0");
    co_return data["result"];
}, "calling " << method << " on " << locator_); }

}
