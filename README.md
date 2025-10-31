# Triedis

A small server for managing in-memory tries.

## Compile

Run `zig build`. Tested on zig 0.14.1.

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

| Command           | Description                     | Example           |
|-------------------|---------------------------------|-------------------|
| SET Key Value     | Insert a value into a trie key  | SET mytrie castle |
| GET Key Value     | Check if trie contains a word   | GET mytrie castle |
| TPREFIX Key Value | Return all words with a prefix  | TPREFIX mytrie ca |

### Inline commands

Triedis also accepts the commands raw over a tcp connection, without any encoding.
In RESP terms this is called inline commands.

## Roadmap

* ~~Add client concurrency through event loop or thread pool~~
* Implement the [Redis serialization protocol](https://redis.io/docs/latest/develop/reference/protocol-spec/)
* Implement more efficient tries through radix trees
