import { Injectable, UnauthorizedException, BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../../users/services/users.service';
import { ConfigService } from '../../../config/config.service';
import { TokenService } from './token.service';
import { ClientApp, Role } from '../common/auth.constants';
import * as bcrypt from 'bcryptjs';
import axios from 'axios';
import { RefreshSessionService } from './refresh-session-service';
import { UserDevice } from 'src/modules/users/schemas/user-device.schema';
import { UserDevicesService } from '../../users/services/user-devices.service';
import { CustomerProfile } from 'src/modules/customers/schemas';
import { CustomerProfilesService } from 'src/modules/customers/services/customer-profile.service';
import { DriverProfilesService } from 'src/modules/drivers/services/driver-profiles.service';
import { DriverOnboardingSubmitDto } from 'src/modules/drivers/dtos/driver-onboarding-submit.dto';
import { DriverOnboardingDraftDto } from 'src/modules/drivers/dtos/driver-onboarding-draft.dto';
import { UserStatus } from 'src/modules/users/schemas/user.schema';
function safeFullName(fullName: string | undefined, email: string) {
  const cleaned = (fullName ?? '').replace(/\bundefined\b/gi, '').trim();
  return cleaned.length ? cleaned : email.split('@')[0];
}
export interface AuthContext {
  app: ClientApp;
  deviceId: string | null;
}
// shape từ GoogleStrategy/GithubStrategy.validate()
type OAuthUser = {
  provider: 'google' | 'github';
  provider_id: string;
  email?: string;
  full_name?: string;
  avatar_url?: string;
};

@Injectable()
export class AuthService {
  constructor(
    private jwtService: JwtService,
    private usersService: UsersService,
    private configService: ConfigService,
    private tokenService: TokenService,
    private refreshSessionService: RefreshSessionService,
    private userDevicesService: UserDevicesService,
    private customerProfilesService: CustomerProfilesService,
    private driverProfilesService: DriverProfilesService,

  ) { }
  // ===== DRIVER ME =====
  async getMeDriver(userId: string) {
    const user = await this.getUserSafe(userId);

    if (user.role !== 'driver') {
      throw new UnauthorizedException('User is not driver');
    }

    const profile = await this.driverProfilesService.findByUserId(userId);

    return {
      ...user,
      driver_profile: this.mapDriverProfile(profile),
    };
  }
  private mapDriverProfile(profile: any) {
    if (!profile) return null;

    return {
      id_card_number: profile.id_card_number ?? null,
      id_card_front_url: profile.id_card_front_url ?? null,
      id_card_back_url: profile.id_card_back_url ?? null,

      license_number: profile.license_number ?? null,
      license_type: profile.license_type ?? null,
      license_image_url: profile.license_image_url ?? null,
      license_expiry: profile.license_expiry ?? null,

      vehicle_brand: profile.vehicle_brand ?? null,
      vehicle_model: profile.vehicle_model ?? null,
      vehicle_plate: profile.vehicle_plate ?? null,
      vehicle_image_url: profile.vehicle_image_url ?? null,

      verification_status: profile.verification_status ?? 'draft',
      verification_reasons: profile.verification_reasons ?? [],
      verification_note: profile.verification_note ?? null,
      submitted_at: profile.submitted_at ?? null,
      verified_at: profile.verified_at ?? null,
      verified_by: profile.verified_by ?? null,
    };
  }
  // ===== DRIVER DEVICE REGISTER =====
  async registerDriverDevice(
    userId: string,
    dto: { deviceId: string; platform: string; fcmToken?: string | null },
  ) {
    await this.userDevicesService.upsertDevice({
      userId,
      deviceId: dto.deviceId,
      platform: dto.platform,
      fcmToken: dto.fcmToken ?? null,
    });
  }

  // ===== DRIVER OAUTH LOGIN (giống customer, nhưng role=driver + ensure driver_profile) =====
  async loginDriverOAuth(oauth: any, ctx: AuthContext) {
    if (!oauth?.provider || !oauth?.provider_id) {
      throw new BadRequestException('Invalid oauth payload');
    }

    const email = oauth.email?.trim();
    if (!email) throw new BadRequestException('Missing email from provider');

    let user = await this.usersService.findByEmail(email);

    if (!user) {
      user = await this.usersService.create({
        email,
        avatar_url: oauth.avatar_url ?? null,
        full_name: safeFullName(oauth.full_name, email),
        role: 'driver',
        status: UserStatus.ACTIVE, // ✅ chỉ active/inactive
        auth_methods: [oauth.provider],
        oauth_providers: [
          {
            provider: oauth.provider,
            provider_id: oauth.provider_id,
            email,
          },
        ],
      } as any);
    } else {
      const doc: any = user;

      if (doc.role && doc.role !== 'driver') {
        throw new BadRequestException('Email already used by another role');
      }

      const authMethods = new Set([...(doc.auth_methods ?? []), oauth.provider]);
      const providers = Array.isArray(doc.oauth_providers)
        ? doc.oauth_providers
        : [];

      const idx = providers.findIndex((p: any) => p.provider === oauth.provider);
      const row = {
        provider: oauth.provider,
        provider_id: oauth.provider_id,
        email,
      };

      if (idx >= 0) providers[idx] = { ...providers[idx], ...row };
      else providers.push(row);

      const patch: any = {
        role: 'driver',
        status: doc.status ?? UserStatus.ACTIVE, // ✅ không set pending
        auth_methods: Array.from(authMethods),
        oauth_providers: providers,
      };

      if (!doc.avatar_url && oauth.avatar_url) patch.avatar_url = oauth.avatar_url;
      if (!doc.full_name || String(doc.full_name).includes('undefined')) {
        patch.full_name = safeFullName(oauth.full_name, email);
      }

      user = await this.usersService.update(doc._id.toString(), patch);
    }

    const userDoc: any = user;
    const uid = userDoc._id.toString();

    await this.driverProfilesService.ensureForUser(uid);

    const sid = (await this.refreshSessionService.createSession({
      userId: uid,
      deviceId: ctx.deviceId ?? undefined,
      aud: ctx.app,
      role: 'driver',
    })) as string;

    const { access_token } = await this.tokenService.signAccessToken({
      userId: uid,
      email: userDoc.email,
      role: 'driver' as Role,
      aud: ctx.app,
      sid,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: uid,
      email: userDoc.email,
      role: 'driver' as Role,
      aud: ctx.app,
      sid,
    });

    return {
      userId: uid,
      accessToken: access_token,
      refreshToken: refresh_token,
    };
  }

  // ===== DRIVER MOBILE REFRESH (body refreshToken, rotate sid, giống customer) =====
  async refreshDriverMobile(refreshToken: string, app: ClientApp) {
    const payload: any = await this.tokenService.verifyRefreshToken(refreshToken);

    if (payload?.type !== 'refresh') throw new UnauthorizedException('Invalid refresh token type');
    if (payload?.aud !== app) throw new UnauthorizedException('Invalid aud');
    if (payload?.role !== 'driver') throw new UnauthorizedException('Invalid role');

    const userId = payload.sub as string | undefined;
    const sid = payload.sid as string | undefined;
    if (!userId || !sid) throw new UnauthorizedException('Missing sub/sid');

    const session = await this.refreshSessionService.getSession(sid);
    if (!session) throw new UnauthorizedException('Refresh session revoked');

    const newSid = (await this.refreshSessionService.rotateSession(sid, {
      userId,
      aud: app,
      role: 'driver',
    })) as string;

    const u = await this.usersService.findById(userId);
    if (!u) throw new UnauthorizedException('User not found');
    const userDoc: any = u;

    const { access_token } = await this.tokenService.signAccessToken({
      userId,
      email: userDoc.email,
      role: 'driver' as Role,
      aud: app,
      sid: newSid,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId,
      email: userDoc.email,
      role: 'driver' as Role,
      aud: app,
      sid: newSid,
    });

    return { accessToken: access_token, refreshToken: refresh_token };
  }

  // ===== DRIVER LOGOUT (revoke sid by refreshToken) =====
  async logoutDriverMobile(refreshToken?: string) {
    if (!refreshToken) return;
    try {
      const payload: any = await this.tokenService.verifyRefreshToken(refreshToken);
      const sid = payload?.sid as string | undefined;
      if (sid) await this.refreshSessionService.revokeSession(sid);
    } catch {
      // ignore
    }
  }


  // ===== ONBOARDING SUBMIT (step 5) =====
  async submitDriverOnboarding(userId: string, dto: DriverOnboardingSubmitDto) {
    const existing = await this.usersService.findByPhone(dto.phone);
    if (existing && (existing as any)._id.toString() !== userId) {
      throw new BadRequestException('Phone already registered');
    }

    await this.usersService.update(
      userId,
      {
        phone: dto.phone,
        avatar_url: dto.avatarUrl ?? null, // ✅ cập nhật avatar user
        status: UserStatus.ACTIVE,         // ✅ chỉ giữ active/inactive
      } as any,
    );

    const patch: any = {
      id_card_number: dto.idCardNumber,
      id_card_front_url: dto.idCardFrontUrl,
      id_card_back_url: dto.idCardBackUrl,

      license_number: dto.licenseNumber,
      license_type: dto.licenseType,
      license_image_url: dto.licenseImageUrl,
      license_expiry: new Date(dto.licenseExpiry),

      vehicle_brand: dto.vehicleBrand,
      vehicle_model: dto.vehicleModel,
      vehicle_plate: dto.vehiclePlate,
      vehicle_image_url: dto.vehicleImageUrl,
    };

    await this.driverProfilesService.ensureForUser(userId);
    await this.driverProfilesService.submit(userId, patch);

    // ✅ trả full me để FE đọc luôn
    return this.getMeDriver(userId);
  }
  // ✅ helper trả user safe cho FE
  async getUserSafe(userId: string) {
    const u = await this.usersService.findById(userId);
    if (!u) throw new UnauthorizedException('User not found');

    const doc: any = u;

    return {
      id: doc._id?.toString(),
      email: doc.email ?? null,
      phone: doc.phone ?? null,
      full_name: doc.full_name ?? null,
      status: doc.status ?? UserStatus.ACTIVE,
      role: doc.role,
      avatar_url: doc.avatar_url ?? null,
    };
  }s
  async updateCustomerPhone(userId: string, rawPhone: string) {
    const phone = (rawPhone ?? '').replace(/\D/g, '').trim();
    if (!phone) throw new BadRequestException('Invalid phone');

    // check trùng phone
    const existing = await this.usersService.findByPhone(phone);
    if (existing && (existing as any)._id.toString() !== userId) {
      throw new BadRequestException('Phone already registered');
    }

    await this.usersService.update(userId, { phone } as any);

    // trả về me để FE update state luôn (có kèm customer_profile)
    return this.getMeCustomer(userId);
  }
  async getMeCustomer(userId: string) {
    const user = await this.getUserSafe(userId);
    const profile = await this.customerProfilesService.findByUserId(userId);

    return {
      ...user,
      customer_profile: profile ?? null,
    };
  }
  async registerCustomerDevice(userId: string, dto: { deviceId: string; platform: string; fcmToken?: string | null }) {
    await this.userDevicesService.upsertDevice({
      userId,
      deviceId: dto.deviceId,
      platform: dto.platform,
      fcmToken: dto.fcmToken ?? null,
    });
  }
  // =========================
  // CUSTOMER OAUTH LOGIN
  // =========================
  async loginCustomerOAuth(oauth: OAuthUser, ctx: AuthContext) {
    if (!oauth?.provider || !oauth?.provider_id) {
      throw new BadRequestException('Invalid oauth payload');
    }

    // Google thường có email, GitHub có thể null -> bạn đã fallback ở GithubStrategy (email giả)
    const email = oauth.email?.trim();
    if (!email) throw new BadRequestException('Missing email from provider');

    // 1) find user by email
    let user = await this.usersService.findByEmail(email);

    // 2) nếu chưa có thì create user (⚠️ phone unique index -> cần value unique)
    if (!user) {
      user = await this.usersService.create({
        email,
        // workaround để không vỡ unique index của phone (vì bạn đang để unique không sparse)
        // phone: ``,
        avatar_url: oauth.avatar_url ?? null,
        full_name: safeFullName(oauth.full_name, email),
        role: 'customer',
        status: 'active',
        auth_methods: [oauth.provider],
        oauth_providers: [
          { provider: oauth.provider, provider_id: oauth.provider_id, email },
        ],
      } as any);
    } else {
      const doc: any = user;

      const authMethods = new Set([...(doc.auth_methods ?? []), oauth.provider]);
      const providers = Array.isArray(doc.oauth_providers) ? doc.oauth_providers : [];

      const idx = providers.findIndex((p: any) => p.provider === oauth.provider);
      const row = { provider: oauth.provider, provider_id: oauth.provider_id, email };

      if (idx >= 0) providers[idx] = { ...providers[idx], ...row };
      else providers.push(row);

      const patch: any = {
        auth_methods: Array.from(authMethods),
        oauth_providers: providers,
      };

      if (!doc.avatar_url && oauth.avatar_url) patch.avatar_url = oauth.avatar_url;
      if (!doc.full_name || String(doc.full_name).includes('undefined')) {
        patch.full_name = safeFullName(oauth.full_name, email);
      }

      user = await this.usersService.update(doc._id.toString(), patch);
    }

    const userDoc: any = user;
    const uid = userDoc._id.toString();
    await this.customerProfilesService.ensureForUser(uid);
    // 3) create Redis session sid
    const sid = (await this.refreshSessionService.createSession({
      userId: uid,
      deviceId: ctx.deviceId ?? undefined,
      aud: ctx.app,
      role: 'customer',
    })) as string;

    // 4) sign tokens (aud customer_mobile + sid)
    const { access_token } = await this.tokenService.signAccessToken({
      userId: uid,
      email: userDoc.email,
      role: 'customer' as Role,
      aud: ctx.app,
      sid,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: uid,
      email: userDoc.email,
      role: 'customer' as Role,
      aud: ctx.app,
      sid,
    });

    // ✅ key đồng nhất cho mobile
    return {
      userId: uid,
      accessToken: access_token,
      refreshToken: refresh_token,
    };
  }

  // =========================
  // CUSTOMER MOBILE REFRESH (body refreshToken)
  // =========================
  async refreshCustomerMobile(refreshToken: string, app: ClientApp) {
    const payload: any = await this.tokenService.verifyRefreshToken(refreshToken);

    if (payload?.type !== 'refresh') throw new UnauthorizedException('Invalid refresh token type');
    if (payload?.aud !== app) throw new UnauthorizedException('Invalid aud');
    if (payload?.role !== 'customer') throw new UnauthorizedException('Invalid role');

    const userId = payload.sub as string | undefined;
    const sid = payload.sid as string | undefined;
    if (!userId || !sid) throw new UnauthorizedException('Missing sub/sid');

    // ✅ check session exists
    const session = await this.refreshSessionService.getSession(sid);
    if (!session) throw new UnauthorizedException('Refresh session revoked');

    // ✅ rotate sid
    const newSid = (await this.refreshSessionService.rotateSession(sid, {
      userId,
      aud: app,
      role: 'customer',
    })) as string;

    const u = await this.usersService.findById(userId);
    if (!u) throw new UnauthorizedException('User not found');
    const userDoc: any = u;

    const { access_token } = await this.tokenService.signAccessToken({
      userId,
      email: userDoc.email,
      role: 'customer' as Role,
      aud: app,
      sid: newSid,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId,
      email: userDoc.email,
      role: 'customer' as Role,
      aud: app,
      sid: newSid,
    });

    return {
      accessToken: access_token,
      refreshToken: refresh_token,
    };
  }

  // =========================
  // CUSTOMER LOGOUT (revoke by refreshToken)
  // =========================
  async logoutCustomerMobile(refreshToken?: string) {
    if (!refreshToken) return;

    try {
      const payload: any = await this.tokenService.verifyRefreshToken(refreshToken);
      const sid = payload?.sid as string | undefined;
      if (sid) await this.refreshSessionService.revokeSession(sid);
    } catch {
      // ignore (logout vẫn OK)
    }
  }
  async findUserByEmail(email: string) {
    return this.usersService.findByEmail(email);
  }

  async findUserById(id: string) {
    return this.usersService.findOne(id);
  }

  async createUser(data: {
    email: string;
    phone: string;
    password_hash: string;
    full_name: string;
    role: string;
    status: string;
    auth_methods: string[];
  }) {
    const user = await this.usersService.create({
      email: data.email,
      phone: data.phone,
      password_hash: data.password_hash,
      full_name: data.full_name,
      role: data.role,
      status: data.status,
      auth_methods: data.auth_methods,
    } as any);
    return user;
  }

  async validateUser(email: string, password: string): Promise<any> {
    const user = await this.usersService.findByEmail(email);

    // User không tồn tại
    if (!user) {
      console.log('[AuthService.validateUser] User not found:', email);
      throw new BadRequestException('Người dùng không tồn tại, vui lòng đăng ký');
    }

    const userDoc = user as any;

    // User không có password (có thể đăng nhập bằng social)
    if (!userDoc.password_hash) {
      console.log('[AuthService.validateUser] No password_hash for user:', email);
      throw new BadRequestException('Email hoặc mật khẩu không đúng');
    }

    // Password sai
    const isPasswordValid = await bcrypt.compare(password, userDoc.password_hash);
    if (!isPasswordValid) {
      console.log('[AuthService.validateUser] Invalid password for user:', email);
      throw new BadRequestException('Email hoặc mật khẩu không đúng');
    }

    // User bị blocked
    if (userDoc.status === 'blocked') {
      console.log('[AuthService.validateUser] User is blocked:', email, 'status:', userDoc.status);
      throw new UnauthorizedException('Tài khoản bị khóa, vui lòng liên hệ hỗ trợ');
    }

    console.log('[AuthService.validateUser] User validated successfully:', email, 'role:', userDoc.role, 'status:', userDoc.status);
    return user;
  }

  async validateEmailLogin(email: string, password: string): Promise<any> {
    return this.validateUser(email, password);
  }

  // ==================== MERCHANT METHODS ====================

  async createMerchantUser(data: {
    email: string;
    password: string;
    full_name: string;
    phone: string;
  }) {
    console.log('[AuthService.createMerchantUser] Starting for:', data.email);

    // Check email
    const existingUserByEmail = await this.usersService.findByEmail(data.email);
    if (existingUserByEmail) {
      console.log('[AuthService.createMerchantUser] Email already exists');
      throw new BadRequestException('Email đã được đăng ký');
    }

    // Check phone
    const existingUserByPhone = await this.usersService.findByPhone(data.phone);
    if (existingUserByPhone) {
      console.log('[AuthService.createMerchantUser] Phone already exists:', data.phone);
      throw new BadRequestException('Số điện thoại đã được sử dụng');
    }

    const password_hash = await bcrypt.hash(data.password, 10);

    console.log('[AuthService.createMerchantUser] Calling usersService.create...');

    try {
      const user = await this.usersService.create({
        email: data.email,
        phone: data.phone,
        password_hash,
        full_name: data.full_name,
        role: 'merchant',
        status: 'active',
        auth_methods: ['password'],
      } as any);

      console.log('[AuthService.createMerchantUser] User created:', { id: (user as any)?._id, email: (user as any)?.email });
      return user;
    } catch (error: any) {
      // Handle MongoDB duplicate key error
      if (error.code === 11000) {
        if (error.message.includes('phone')) {
          throw new BadRequestException('Số điện thoại đã được sử dụng');
        }
        if (error.message.includes('email')) {
          throw new BadRequestException('Email đã được đăng ký');
        }
      }
      throw error;
    }
  }

  async registerMerchant(data: any, ctx: AuthContext) {
    const { email, password, full_name, phone } = data;

    const existingUser = await this.usersService.findByEmail(email);
    if (existingUser) {
      throw new BadRequestException('Email already registered');
    }

    const password_hash = await bcrypt.hash(password, 10);

    const user = await this.usersService.create({
      email,
      phone,
      password_hash,
      full_name,
      role: 'merchant',
      status: 'pending_onboarding',
      auth_methods: ['password'],
    } as any);

    const userDoc = user as any;

    const { access_token } = await this.tokenService.signAccessToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'merchant',
      aud: ctx.app,
      sid: undefined,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'merchant',
      aud: ctx.app,
      sid: undefined,
    });

    return {
      access_token,
      refresh_token,
      user: {
        id: userDoc._id,
        email: userDoc.email,
        role: userDoc.role,
        status: userDoc.status,
      },
      onboarding: true,
    };
  }

  async loginMerchant(data: any, ctx: AuthContext) {
    const { email, password } = data;

    const user = await this.validateUser(email, password);
    const userDoc = user as any;

    if (userDoc.role !== 'merchant') {
      throw new UnauthorizedException('Invalid credentials');
    }

    const { access_token } = await this.tokenService.signAccessToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'merchant',
      aud: ctx.app,
      sid: undefined,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'merchant',
      aud: ctx.app,
      sid: undefined,
    });

    return {
      access_token,
      refresh_token,
      user: {
        id: userDoc._id,
        email: userDoc.email,
        role: userDoc.role,
        status: userDoc.status,
      },
      onboarding: userDoc.status === 'pending_onboarding',
    };
  }

  // ==================== CUSTOMER OTP METHODS ====================

  async loginCustomerOtp(data: { phone: string; otp: string }, ctx: AuthContext) {
    // TODO: Implement OTP verification via OtpRedisService
    // const isValid = await this.otpRedisService.verifyOtp(data.phone, data.otp);
    // if (!isValid) throw new UnauthorizedException('Invalid OTP');

    // For now, just find or create user
    let user = await this.usersService.findByPhone(data.phone);

    if (!user) {
      user = await this.usersService.create({
        phone: data.phone,
        full_name: '',
        role: 'customer',
        status: 'active',
        auth_methods: ['phone_otp'],
      } as any);
    }

    const userDoc = user as any;

    const { access_token } = await this.tokenService.signAccessToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'customer',
      aud: ctx.app,
      sid: undefined,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'customer',
      aud: ctx.app,
      sid: undefined,
    });

    return {
      access_token,
      refresh_token,
      user: {
        id: userDoc._id,
        phone: userDoc.phone,
        role: 'customer',
      },
    };
  }

  async registerCustomerOtp(data: { phone: string; otp: string; full_name: string }, ctx: AuthContext) {
    // TODO: Implement OTP verification
    // const isValid = await this.otpRedisService.verifyOtp(data.phone, data.otp);
    // if (!isValid) throw new UnauthorizedException('Invalid OTP');

    const existingUser = await this.usersService.findByPhone(data.phone);
    if (existingUser) {
      throw new BadRequestException('Phone already registered');
    }

    const user = await this.usersService.create({
      phone: data.phone,
      full_name: data.full_name,
      role: 'customer',
      status: 'active',
      auth_methods: ['phone_otp'],
    } as any);

    const userDoc = user as any;

    const { access_token } = await this.tokenService.signAccessToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'customer',
      aud: ctx.app,
      sid: undefined,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: userDoc._id.toString(),
      email: userDoc.email,
      role: 'customer',
      aud: ctx.app,
      sid: undefined,
    });

    return {
      access_token,
      refresh_token,
      user: {
        id: userDoc._id,
        phone: userDoc.phone,
        full_name: userDoc.full_name,
        role: 'customer',
      },
    };
  }

  // ==================== DRIVER OTP METHODS ====================



  async refresh(user: { userId: string; role: string; aud: string; sid?: string }) {
    const userDoc = await this.usersService.findOne(user.userId);
    if (!userDoc) {
      throw new UnauthorizedException('User not found');
    }

    const userData = userDoc as any;

    const { access_token } = await this.tokenService.signAccessToken({
      userId: user.userId,
      email: userData.email,
      role: user.role as Role,
      aud: user.aud as ClientApp,
      sid: user.sid,
    });

    const { refresh_token } = await this.tokenService.signRefreshToken({
      userId: user.userId,
      email: userData.email,
      role: user.role as Role,
      aud: user.aud as ClientApp,
      sid: user.sid,
    });

    return { access_token, refresh_token };
  }

  // ==================== OAUTH METHODS (giữ nguyên) ====================

  async verifyOAuthToken(provider: string, idToken: string): Promise<any> {
    try {
      let payload: any;
      switch (provider) {
        case 'google':
          payload = await this.verifyGoogleToken(idToken);
          break;
        case 'github':
          payload = await this.verifyGithubToken(idToken);
          break;
        default:
          throw new BadRequestException('Unsupported OAuth provider');
      }
      return payload;
    } catch (error) {
      throw new UnauthorizedException('Invalid OAuth token');
    }
  }

  private async verifyGoogleToken(idToken: string): Promise<any> {
    const response = await axios.get(
      `https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=${idToken}`,
    );
    if (response.data.aud !== this.configService.googleClientId) {
      throw new UnauthorizedException('Invalid Google token');
    }
    return {
      provider: 'google',
      provider_id: response.data.sub,
      email: response.data.email,
      full_name: response.data.name,
      avatar_url: response.data.picture,
    };
  }

  private async verifyGithubToken(accessToken: string): Promise<any> {
    const response = await axios.get('https://api.github.com/user', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    return {
      provider: 'github',
      provider_id: response.data.id.toString(),
      email: response.data.email,
      full_name: response.data.name || response.data.login,
      avatar_url: response.data.avatar_url,
    };
  }

  async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, 10);
  }
}
