# Orchid

Orchid is a decentralized marketplace "for bandwidth"; providers run a server (in the srv-shared folder) that talks to a decentralized directory that runs on Ethereum (in the dir-ethereum folder). On top of this marketplace, we happen to provide a VPN application (the app- and vpn- folders) as well as a lower-level client daemon (currently in cli-shared); but, as our software is (and has always been ;P) entirely open-source (under a "free software" license: the AGPLv3)--and, because we strive to use "off the shelf" transport protocols whenever possible (such as WebRTC and, maybe-weirdly, layered UDP)--you can remix our stack into anything you want! Users pay for service using "(streaming) probablistic nanopayments"--a "layer 2" Ethereum scaling solution we think of as somewhere between "one-to-many payment channels" and "probablistic roll-ups", based on some older (yet seminal) work into which we poured effort into economic incentive design and practical integration--that is "somewhat separate", in case you'd want to use it for something else (you can find the code for this in lot-ethereum).

## Building

To build any Orchid sub-project, you need to have the usual (complete) set of GNU build tools installed (such as autotools, bison/flex, make... you know, "the works" ;P) and (specifically) clang (I'm truly sorry... maybe one day we'll support gcc). Some of the build scripts for our dependencies use Python (I think only 3.x), one insists on being built using meson/ninja, and we use a couple libraries that are written in Rust. FWIW, the "usual algorithm" of "try to build it, and if you get an error saying you are missing X, just install X" should  work, so I'd just dive in (like, I'm surprised you are even reading the README, am I right or am I right? ;P); that said, if you are "feeling lucky", you can run env/setup-mac.sh or env/setup-lnx.sh (two scripts we provide... you should just read them first) to install most of what you'd want. Don't forget to do a "git submodule update --init --recursive", and then you should be able to build a client or server for whatever platform you want by just going into the appropriate folder (such as app-{android,ios}, or {cli,srv}-shared) and running "make".
