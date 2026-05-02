// src/config/config.service.ts
import { Injectable } from '@nestjs/common';

@Injectable()
export class ConfigService {
  private readonly env = process.env;

  /**
   * Lấy biến môi trường theo key.
   * - Nếu không có thì trả về defaultValue (nếu truyền)
   * - Có thể ép kiểu bằng generic T
   */
  // ✅ Implement get() để dùng kiểu this.config.get<string>('TRACKASIA_KEY')
  get<T = string>(key: string, defaultValue?: T): T | undefined {
    const v = this.env[key];
    if (v == null) return defaultValue;
    return v as unknown as T;
  }

  getOrThrow<T = string>(key: string): T {
    const v = this.get<T>(key);
    if (v === undefined) throw new Error(`${key} is missing`);
    return v;
  }

  // ====== GIỮ NGUYÊN CÁC GETTER CỦA BẠN ======

  get mongoUri(): string {
    return this.env.MONGO_URI || 'mongodb://localhost:27017/fabo2o';
  }
  get trackAsiaKey(): string {
    return this.env.TRACKASIA_KEY || '';
  }
  get jwtSecret(): string {
    return this.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production';
  }

  get jwtRefreshSecret(): string {
    return this.env.JWT_REFRESH_SECRET || 'your-super-secret-refresh-key-change-in-production';
  }

  get jwtExpirationSeconds(): number {
    return parseInt(this.env.JWT_EXPIRATION_SECONDS || '3600');
  }

  get jwtRefreshExpirationSeconds(): number {
    return parseInt(this.env.JWT_REFRESH_EXPIRATION_SECONDS || '604800');
  }

  get port(): number {
    return parseInt(this.env.PORT || '4000');
  }

  get nodeEnv(): string {
    return this.env.NODE_ENV || 'development';
  }

  get isDevelopment(): boolean {
    return this.nodeEnv === 'development';
  }

  get redisHost(): string {
    return this.env.REDIS_HOST || 'localhost';
  }

  get redisPort(): number {
    return parseInt(this.env.REDIS_PORT || '6379');
  }

  get redisPassword(): string | undefined {
    return this.env.REDIS_PASSWORD;
  }

  get googleClientId(): string {
    return this.env.GOOGLE_CLIENT_ID || '';
  }

  get googleClientSecret(): string {
    return this.env.GOOGLE_CLIENT_SECRET || '';
  }

  get googleCallbackUrl(): string {
    return this.env.GOOGLE_CALLBACK_URL || 'http://localhost:4000/auth/oauth/google/callback';
  }

  get facebookClientId(): string {
    return this.env.FACEBOOK_CLIENT_ID || '';
  }

  get facebookClientSecret(): string {
    return this.env.FACEBOOK_CLIENT_SECRET || '';
  }

  get facebookCallbackUrl(): string {
    return this.env.FACEBOOK_CALLBACK_URL || 'http://localhost:4000/auth/oauth/facebook/callback';
  }

  get githubClientId(): string {
    return this.env.GITHUB_CLIENT_ID || '';
  }

  get githubClientSecret(): string {
    return this.env.GITHUB_CLIENT_SECRET || '';
  }

  get githubCallbackUrl(): string {
    return this.env.GITHUB_CALLBACK_URL || 'http://localhost:4000/auth/oauth/github/callback';
  }

  get frontendUrl(): string {
    return this.env.FRONTEND_URL || 'http://localhost:3000';
  }

  get rateLimitMax(): number {
    return parseInt(this.env.RATE_LIMIT_MAX || '100');
  }

  get rateLimitWindowMs(): number {
    return parseInt(this.env.RATE_LIMIT_WINDOW_MS || '60000');
  }

  get otpExpirySeconds(): number {
    return parseInt(this.env.OTP_EXPIRY_SECONDS || '300');
  }

  get sessionExpiryDays(): number {
    return parseInt(this.env.SESSION_EXPIRY_DAYS || '30');
  }

  get driverMaxDevices(): number {
    return parseInt(this.env.DRIVER_MAX_DEVICES || '3');
  }

  get customerMaxDevices(): number {
    return parseInt(this.env.CUSTOMER_MAX_DEVICES || '5');
  }

  get loginAttemptsBeforeLockout(): number {
    return parseInt(this.env.LOGIN_ATTEMPTS_LOCKOUT || '5');
  }

  get lockoutDurationMinutes(): number {
    return parseInt(this.env.LOCKOUT_DURATION_MINUTES || '15');
  }

  get cloudinaryName(): string {
    return this.env.CLOUDINARY_NAME || '';
  }

  get cloudinaryApiKey(): string {
    return this.env.CLOUDINARY_API_KEY || '';
  }

  get cloudinaryApiSecret(): string {
    return this.env.CLOUDINARY_API_SECRET || '';
  }

  get resendApiKey(): string {
    return this.env.RESEND_API_KEY || '';
  }

  // Kafka Configuration
  get kafkaBrokers(): string {
    return this.env.KAFKA_BROKERS || 'localhost:9092';
  }

  get kafkaClientId(): string {
    return this.env.KAFKA_CLIENT_ID || 'fab-o2o-api';
  }

  get kafkaGroupId(): string {
    return this.env.KAFKA_GROUP_ID || 'fab-o2o-api-consumer';
  }

  get kafkaEnabled(): string {
    return this.env.KAFKA_ENABLED || 'false';
  }
}
