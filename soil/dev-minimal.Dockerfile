FROM debian:buster-slim

RUN apt-get update

# Copy this file into the container so we can run it.
WORKDIR /app
COPY soil/image-deps.sh .

RUN ./image-deps.sh dev-minimal

RUN ./image-deps.sh dev-minimal-py

CMD ["sh", "-c", "echo 'hello from oilshell/soil-dev-minimal buildkit'"]