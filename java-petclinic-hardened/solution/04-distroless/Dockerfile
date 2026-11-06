# ---- Stage 1 : construire le JAR et le healthcheck, avec Maven et un JDK ----
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# Le healthcheck, compilé ici : l'image finale n'a ni curl, ni shell, ni compilateur
COPY healthcheck/HealthCheck.java ./
RUN javac -d /src/hc HealthCheck.java

# ---- Stage 2 : exécuter le JAR, avec un JRE distroless ----
# distroless ne publie pas de tag de version précis : on épingle l'empreinte
FROM gcr.io/distroless/java21-debian13:nonroot@sha256:b22857e939bd95abd69d9d747f0421a274f9f70855ecfc335f7d97f6eeef578d AS runtime

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution distroless" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
EXPOSE 8080

# La forme exec est obligatoire : il n'y a pas de shell pour interpréter une chaîne
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/bin/java", "-Xmx16m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-cp", "/app/hc", "HealthCheck"]

COPY --from=build /src/petclinic.jar /app/petclinic.jar
COPY --from=build /src/hc /app/hc

# L'utilisateur nonroot (UID 65532) existe déjà dans l'image : on le déclare
USER nonroot
ENTRYPOINT ["/usr/bin/java", "-jar", "/app/petclinic.jar"]
