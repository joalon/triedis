# Triedis

A small server for managing in-memory tries.

## Compile

Run `zig build`. Tested on zig 0.15.2.

## Usage

The server is a static binary, run it with `./triedis`.

An example run with netcat against the server:

```bash
$ nc localhost 4657
set mytrie "cat"
set mytrie "category"
set mytrie "cathedral"
set mytrie "castle"
tprefix mytrie "cat"
cat
category
cathedral
```

## Commands

A Redis compatible client sends command encoded as an array of bulk strings,
according to the RESP protocol.

### Reference

SET     - Insert a string into a trie key
GET     - Check if trie contains a word
TPREFIX - Return all words with a prefix

### Inline commands

Triedis also accepts the commands raw over a tcp connection, without any encoding.
In RESP terms this is called inline commands.

## Roadmap

* ~~Add client concurrency through event loop or thread pool~~
* Implement the [Redis serialization protocol](https://redis.io/docs/latest/develop/reference/protocol-spec/)
* Implement more efficient tries through radix trees
