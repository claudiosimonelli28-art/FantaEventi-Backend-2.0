# Use official Dart SDK image to build and run
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# Build minimal runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8088

CMD ["/app/bin/server"]
