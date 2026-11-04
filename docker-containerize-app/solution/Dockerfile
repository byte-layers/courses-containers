# Solution du lab « Conteneuriser getting-started-app ».
# À ne regarder qu'en cas de blocage : les étapes du lab vous y mènent.
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
RUN mkdir -p /etc/todos && chown node /etc/todos
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
