# Triedis

A small server for managing in-memory tries.

## Compile

Run `zig build`. Tested on zig 0.15.2.

## Usage

The server is a static binary, run it with `./triedis`.

An example run with netcat against the server:

```bash
$ nc localhost 4657
insert mytrie cat
insert mytrie category
insert mytrie cathedral
insert mytrie castle
prefixsearch mytrie cat
cat
category
cathedral
```

## Roadmap

* ~~Add client concurrency through event loop or thread pool~~
* Implement the [Redis serialization protocol](https://redis.io/docs/latest/develop/reference/protocol-spec/)
* Run property tests on Trie module
* Implement more efficient tries through radix trees
