FROM maven
COPY . /app
WORKDIR /app
RUN mvn package -DskipTests
EXPOSE 8080
CMD java -jar target/*.jar
