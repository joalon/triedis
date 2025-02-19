# Triedis

A small server for managing in-memory tries.

## Usage

The server is a static binary, run it with `./triedis`. For options, use `-h`.

An example run with netcat against the server:

```bash
$ nc localhost 4657
create mytrie
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

* Add client concurrency through event loop or thread pool
* Implement more efficient tries through radix trees
