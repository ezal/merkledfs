FROM ocaml/opam:alpine-3.19

RUN sudo apk add --no-cache m4 gcc gmp-dev musl-dev openssl-dev

USER opam
COPY . merkledfs
WORKDIR merkledfs

USER root
RUN chown -R opam:opam .
USER opam

RUN opam install --deps-only .
RUN eval $(opam env) && dune build

# just for convenience
RUN cp _build/default/src/bin/server.exe .

CMD ["./server.exe"]
