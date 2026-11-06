# ---- Stage 1 : construire le JAR, avec Maven et un JDK ----
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src

# Les dépendances d'abord : cette couche ne change que si pom.xml change
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

# Le code ensuite : il change souvent, et seule cette partie se reconstruit
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/spring-petclinic-*.jar /src/petclinic.jar

# ---- Stage 2 : exécuter le JAR, avec un JRE seul ----
FROM eclipse-temurin:21.0.13_9-jre-noble AS runtime

LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN groupadd --system --gid 10001 petclinic \
 && useradd --system --uid 10001 --gid petclinic --no-create-home --shell /usr/sbin/nologin petclinic

WORKDIR /app
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

# Du stage build, on ne prend que le JAR
COPY --from=build /src/petclinic.jar /app/petclinic.jar

USER petclinic
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
