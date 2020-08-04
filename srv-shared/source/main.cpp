/* Orchid - WebRTC P2P VPN Market (on Ethereum)
 * Copyright (C) 2017-2019  The Orchid Authors
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


#include <cstdio>
#include <iostream>
#include <regex>

#include <unistd.h>

#include <boost/program_options/parsers.hpp>
#include <boost/program_options/options_description.hpp>
#include <boost/program_options/variables_map.hpp>

#include <libplatform/libplatform.h>
#include <v8.h>

#include <api/jsep_session_description.h>
#include <pc/webrtc_sdp.h>

#include <rtc_base/message_digest.h>
#include <rtc_base/openssl_identity.h>
#include <rtc_base/ssl_fingerprint.h>

#include "baton.hpp"
#include "boring.hpp"
#include "cashier.hpp"
#include "channel.hpp"
#include "coinbase.hpp"
#include "egress.hpp"
#include "jsonrpc.hpp"
#include "load.hpp"
#include "local.hpp"
#include "market.hpp"
#include "node.hpp"
#include "router.hpp"
#include "scope.hpp"
#include "server.hpp"
#include "store.hpp"
#include "task.hpp"
#include "transport.hpp"
#include "utility.hpp"
#include "version.hpp"

namespace orc {

namespace po = boost::program_options;

int Main(int argc, const char *const argv[]) {
    po::variables_map args;

    po::options_description group("general command line");
    group.add_options()
        ("help", "produce help message")
        ("version", "dump version (intense)")
    ;

    po::options_description options;

    { po::options_description group("orchid eth addresses");
    group.add_options()
        //("token", po::value<std::string>()->default_value("0x4575f41308EC1483f3d399aa9a2826d74Da13Deb"))
        ("lottery", po::value<std::string>()->default_value("0xb02396f06CC894834b7934ecF8c8E5Ab5C1d12F1"))
        ("location", po::value<std::string>()->default_value("0xEF7bc12e0F6B02fE2cb86Aa659FdC3EBB727E0eD"))
    ; options.add(group); }

    { po::options_description group("user eth addresses");
    group.add_options()
        ("personal", po::value<std::string>(), "address to use for making transactions")
        ("password", po::value<std::string>()->default_value(""), "password to unlock personal account")
        ("recipient", po::value<std::string>(), "deposit address for client payments")
        ("provider", po::value<std::string>(), "provider address in stake directory")
    ; options.add(group); }

    { po::options_description group("external resources");
    group.add_options()
        ("chainid", po::value<unsigned>()->default_value(1), "ropsten = 3; rinkeby = 4; goerli = 5")
        ("rpc", po::value<std::string>()->default_value("http://127.0.0.1:8545/"), "ethereum json/rpc private API endpoint")
        ("ws", po::value<std::string>()->default_value("ws://127.0.0.1:8546/"), "ethereum websocket private API endpoint")
        ("stun", po::value<std::string>()->default_value("stun.l.google.com:19302"), "stun server url to use for discovery")
    ; options.add(group); }

    { po::options_description group("webrtc signaling");
    group.add_options()
        ("host", po::value<std::string>(), "external hostname for this server")
        ("bind", po::value<std::string>()->default_value("0.0.0.0"), "ip address for server to bind to")
        ("port", po::value<uint16_t>()->default_value(8443), "port to advertise on blockchain")
        ("tls", po::value<std::string>(), "tls keys and chain (pkcs#12 encoded)")
        ("dh", po::value<std::string>(), "diffie hellman params (pem encoded)")
        ("network", po::value<std::string>(), "local interface for ICE candidates")
    ; options.add(group); }

    { po::options_description group("bandwidth pricing");
    group.add_options()
        ("currency", po::value<std::string>()->default_value("USD"), "currency used for price conversions")
        ("price", po::value<std::string>()->default_value("0.03"), "price of bandwidth in currency / GB")
    ; options.add(group); }

    { po::options_description group("packet egress");
    group.add_options()
        ("openvpn", po::value<std::string>(), "OpenVPN .ovpn configuration file")
        ("wireguard", po::value<std::string>(), "WireGuard .conf configuration file")
    ; options.add(group); }

    po::positional_options_description positional;

    po::store(po::command_line_parser(argc, argv).options(po::options_description()
        .add(group)
        .add(options)
    ).positional(positional).style(po::command_line_style::default_style
        ^ po::command_line_style::allow_guessing
    ).run(), args);

    if (auto path = getenv("ORCHID_CONFIG"))
        po::store(po::parse_config_file(path, po::options_description()
            .add(options)
        ), args);

    po::notify(args);

    if (args.count("help") != 0) {
        std::cout << po::options_description()
            .add(group)
            .add(options)
        << std::endl;

        return 0;
    }

    if (args.count("version") != 0) {
        std::cout.write(VersionData, VersionSize);
        return 0;
    }


    Initialize();

    std::vector<std::string> ice;
    ice.emplace_back("stun:" + args["stun"].as<std::string>());


    const auto params(args.count("dh") == 0 ? Params() : Load(args["dh"].as<std::string>()));


    const auto store([&]() -> Store {
        if (args.count("tls") != 0)
            return Load(args["tls"].as<std::string>());
        else {
            const auto pem(Certify()->ToPEM());
            auto key(pem.private_key());
            auto chain(pem.certificate());

            // XXX: generate .p12 file (for Nathan)
            std::cerr << key << std::endl;
            std::cerr << chain << std::endl;

            return Store(std::move(key), std::move(chain));
        }
    }());


    // XXX: the return type of OpenSSLIdentity::FromPEMStrings should be changed :/
    // NOLINTNEXTLINE (cppcoreguidelines-pro-type-static-cast-downcast)
    //U<rtc::OpenSSLIdentity> identity(static_cast<rtc::OpenSSLIdentity *>(rtc::OpenSSLIdentity::FromPEMStrings(store.Key(), store.Chain()));

    rtc::scoped_refptr<rtc::RTCCertificate> certificate(rtc::RTCCertificate::FromPEM(rtc::RTCCertificatePEM(store.Key(), store.Chain())));
    U<rtc::SSLFingerprint> fingerprint(rtc::SSLFingerprint::CreateFromCertificate(*certificate));


    std::string host;
    if (args.count("host") != 0)
        host = args["host"].as<std::string>();
    else
        // XXX: this should be the IP of "bind"
        host = boost::asio::ip::host_name();

    const auto port(args["port"].as<uint16_t>());

    const Strung url("https://" + host + ":" + std::to_string(port) + "/");
    Bytes gpg;

    Builder tls;
    static const std::regex re("-");
    tls += Object(std::regex_replace(fingerprint->algorithm, re, "").c_str());
    tls += Subset(fingerprint->digest.data(), fingerprint->digest.size());

    std::cerr << "url = " << url << std::endl;
    std::cerr << "tls = " << tls << std::endl;
    std::cerr << "gpg = " << gpg << std::endl;


    Address location(args["location"].as<std::string>());
    std::string password(args["password"].as<std::string>());

    auto origin(args.count("network") == 0 ? Break<Local>() : Break<Local>(args["network"].as<std::string>()));


    {
        const auto offer(Wait(Description(origin, {"stun:stun1.l.google.com:19302", "stun:stun2.l.google.com:19302"})));
        std::cout << std::endl;
        std::cout << Filter(false, offer) << std::endl;

        webrtc::JsepSessionDescription jsep(webrtc::SdpType::kOffer);
        webrtc::SdpParseError error;
        orc_assert(webrtc::SdpDeserialize(offer, &jsep, &error));

        auto description(jsep.description());
        orc_assert(description != nullptr);

        std::map<Socket, Socket> reflexive;

        for (size_t i(0); ; ++i) {
            const auto ices(jsep.candidates(i));
            if (ices == nullptr)
                break;
            for (size_t i(0), e(ices->count()); i != e; ++i) {
                const auto ice(ices->at(i));
                orc_assert(ice != nullptr);
                const auto &candidate(ice->candidate());
                if (candidate.type() != "stun")
                    continue;
                if (!reflexive.emplace(candidate.related_address(), candidate.address()).second) {
                    std::cerr << "server must not use symmetric NAT" << std::endl;
                    return 1;
                }
            }
        }
    }


    auto rpc(Locator::Parse(args["rpc"].as<std::string>()));
    Endpoint endpoint(origin, rpc);

    if (args.count("provider") != 0) {
        const Address provider(args["provider"].as<std::string>());

        Wait([&]() -> task<void> {
            const auto latest(co_await endpoint.Latest());
            static const Selector<std::tuple<uint256_t, Bytes, Bytes, Bytes>, Address> look("look");
            if (Slice<1, 4>(co_await look.Call(endpoint, latest, location, 90000, provider)) != std::tie(url, tls, gpg)) {
                static const Selector<void, Bytes, Bytes, Bytes> move("move");
                co_await move.Send(endpoint, provider, password, location, 3000000, Beam(url), Beam(tls), {});
            }
        }());
    }

    auto cashier([&]() -> S<Cashier> {
        const auto price(Float(args["price"].as<std::string>()) / (1024 * 1024 * 1024));
        if (price == 0)
            return nullptr;

        orc_assert_(args.count("recipient") != 0, "must specify --recipient unless --price is 0");
        const Address recipient(args["recipient"].as<std::string>());

        // XXX: this should switch to a different mechanism (using eth_sendTransaction)
        const Address personal(args.count("personal") == 0 ? "0x0000000000000000000000000000000000000000" : args["personal"].as<std::string>());

        auto cashier(Break<Cashier>(
            std::move(endpoint),
            price, personal, password,
            Address(args["lottery"].as<std::string>()), args["chainid"].as<unsigned>(), recipient
        ));
        cashier->Open(origin, Locator::Parse(args["ws"].as<std::string>()));
        return cashier;
    }());

    auto market(Make<Market>(5*60*1000, origin, Wait(CoinbaseFiat(5*60*1000, origin, args["currency"].as<std::string>()))));

    auto egress([&]() { if (false) {
    } else if (args.count("openvpn") != 0) {
        const auto file(Load(args["openvpn"].as<std::string>()));
        auto egress(Break<BufferSink<Egress>>(0));
        Wait(Connect(*egress, origin, 0, file, "", ""));
        return egress;
    } else if (args.count("wireguard") != 0) {
        const auto file(Load(args["wireguard"].as<std::string>()));
        auto egress(Break<BufferSink<Egress>>(0));
        Wait(Guard(*egress, origin, 0, file));
        return egress;
    } else orc_assert_(false, "must provide an egress option"); }());

    const auto node(Make<Node>(std::move(origin), std::move(cashier), std::move(market), std::move(egress), std::move(ice)));
    node->Run(asio::ip::make_address(args["bind"].as<std::string>()), port, store.Key(), store.Chain(), params);
    return 0;
}

}

int main(int argc, const char *const argv[]) { try {
    v8::V8::InitializeICUDefaultLocation(argv[0]);
    v8::V8::InitializeExternalStartupData(argv[0]);

    const auto platform(v8::platform::NewDefaultPlatform());
    v8::V8::InitializePlatform(platform.get());
    _scope({ v8::V8::ShutdownPlatform(); });

    v8::V8::Initialize();
    _scope({ v8::V8::Dispose(); });
    return orc::Main(argc, argv);
} catch (const std::exception &error) {
    std::cerr << error.what() << std::endl;
    return 1;
} }
