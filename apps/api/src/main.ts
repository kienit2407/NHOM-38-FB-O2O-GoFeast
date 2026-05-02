import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { Transport, MicroserviceOptions } from '@nestjs/microservices';
import * as dotenv from 'dotenv';
import cookieParser from 'cookie-parser';
import { resolve } from 'path';
import { AppModule } from './app.module';
import { ConfigService } from './config/config.service';

dotenv.config({ path: resolve(__dirname, '..', '.env') });

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  // Add cookie parser middleware
  app.use(cookieParser());

  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      transformOptions: {
        enableImplicitConversion: false, // ✅ cực quan trọng
      },
    }),
  );
  app.enableCors({
    origin: [
      'http://localhost:8080',   // merchant-web
      'http://localhost:8088',   // admin-web
    ],
    credentials: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'X-Device-ID', 'x-client-platform', 'x-client-app', 'x-correlation-id', 'x-request-id'],
  });

  app.enableShutdownHooks();

  // const kafkaEnabled = configService.kafkaEnabled === 'true';
  // if (kafkaEnabled) {
  //   const kafkaOptions: MicroserviceOptions = {
  //     transport: Transport.KAFKA,
  //     options: {
  //       client: {
  //         clientId: configService.kafkaClientId || 'fab-o2o-api',
  //         brokers: [configService.kafkaBrokers || 'localhost:9092'],
  //       },
  //       consumer: {
  //         groupId: configService.kafkaGroupId || 'fab-o2o-api-consumer',
  //       },
  //     },
  //   };

  //   app.connectMicroservice<MicroserviceOptions>(kafkaOptions);
  //   logger.log('Kafka microservice enabled');
  // } else {
  //   logger.log('Kafka microservice disabled (KAFKA_ENABLED=false)');
  // }

  // await app.startAllMicroservices();
  await app.listen(configService.port);

  logger.log(`Application is running on: http://localhost:${configService.port}`);
}

bootstrap();
