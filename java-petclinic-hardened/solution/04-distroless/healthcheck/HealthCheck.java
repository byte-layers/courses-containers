import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

// Interroge /actuator/health : code de sortie 0 si l'application répond 200, 1 sinon
public class HealthCheck {
    public static void main(String[] args) {
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/actuator/health"))
                    .timeout(Duration.ofSeconds(2))
                    .build();
            HttpResponse<Void> response = HttpClient.newHttpClient()
                    .send(request, HttpResponse.BodyHandlers.discarding());
            System.exit(response.statusCode() == 200 ? 0 : 1);
        } catch (Exception e) {
            System.exit(1);
        }
    }
}
