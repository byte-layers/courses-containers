# L'image d'exécution : un JRE seul, Java 21, Ubuntu 24.04 (noble)
FROM eclipse-temurin:21.0.13_9-jre-noble

# Les métadonnées de l'image, au format OCI
LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

# Un utilisateur système dédié, sans dossier personnel ni shell de connexion
RUN groupadd --system --gid 10001 petclinic \
 && useradd --system --uid 10001 --gid petclinic --no-create-home --shell /usr/sbin/nologin petclinic

WORKDIR /app

# La JVM prend 75 % de la mémoire accordée au conteneur
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080

# Un healthcheck par défaut, que celui qui lance le conteneur peut remplacer
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

# Ce qui change à chaque version vient en dernier : le JAR, propriété de root
COPY target/spring-petclinic-*.jar /app/petclinic.jar

USER petclinic

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
