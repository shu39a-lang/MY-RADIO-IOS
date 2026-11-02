FROM node:22-alpine
WORKDIR /app
COPY package.json server.js voice.js ./
ENV PORT=8080
USER node
CMD ["node", "server.js"]
