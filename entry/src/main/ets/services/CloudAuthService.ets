import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';

const DOMAIN = 0x0000;
const TAG = 'CloudAuthService';
const BASE_URL = AppConfig.CLOUD_API_BASE_URL;

export interface UserInfo {
  id: string;
  username: string;
  nickname?: string;
  avatar?: string;
  custom_music_server_url?: string;
  qq_music_api_key?: string;
  recording_dir?: string;
  created_at?: string;
  updated_at?: string;
}

export interface AuthTokenResult {
  access_token: string;
  token_type: string;
  expires_in_days: number;
  user: UserInfo;
}

export interface ErrorDetailResponse {
  detail?: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  message?: string;
}

export class CloudAuthService {
  private static instance?: CloudAuthService;

  private constructor() {}

  static getInstance(): CloudAuthService {
    if (!CloudAuthService.instance) {
      CloudAuthService.instance = new CloudAuthService();
    }
    return CloudAuthService.instance;
  }

  async register(username: string, password: string, nickname?: string): Promise<ApiResponse<AuthTokenResult>> {
    const request = http.createHttp();
    try {
      const body = JSON.stringify({
        username: username.trim(),
        password: password,
        nickname: nickname && nickname.trim().length > 0 ? nickname.trim() : username.trim()
      });
      const response = await request.request(`${BASE_URL}/auth/register`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000
      });

      const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const data = JSON.parse(resStr) as AuthTokenResult;
        return { success: true, data: data };
      } else {
        let errMsg = '注册失败';
        try {
          const errObj = JSON.parse(resStr) as ErrorDetailResponse;
          if (errObj && errObj.detail) {
            errMsg = errObj.detail;
          }
        } catch (_) {}
        return { success: false, message: errMsg };
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Register request error: %{public}s', JSON.stringify(err));
      return { success: false, message: '网络连接异常，请检查网络设置' };
    } finally {
      request.destroy();
    }
  }

  async login(username: string, password: string): Promise<ApiResponse<AuthTokenResult>> {
    const request = http.createHttp();
    try {
      const body = JSON.stringify({
        username: username.trim(),
        password: password
      });
      const response = await request.request(`${BASE_URL}/auth/login`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000
      });

      const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const data = JSON.parse(resStr) as AuthTokenResult;
        return { success: true, data: data };
      } else {
        let errMsg = '用户名或密码错误';
        try {
          const errObj = JSON.parse(resStr) as ErrorDetailResponse;
          if (errObj && errObj.detail) {
            errMsg = errObj.detail;
          }
        } catch (_) {}
        return { success: false, message: errMsg };
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Login request error: %{public}s', JSON.stringify(err));
      return { success: false, message: '网络连接异常，请检查网络设置' };
    } finally {
      request.destroy();
    }
  }

  async getMe(token: string): Promise<ApiResponse<UserInfo>> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/auth/me`, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        connectTimeout: 10000,
        readTimeout: 15000
      });

      const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const user = JSON.parse(resStr) as UserInfo;
        return { success: true, data: user };
      } else {
        return { success: false, message: '获取用户信息失败或登录已过期' };
      }
    } catch (err) {
      return { success: false, message: '网络连接异常' };
    } finally {
      request.destroy();
    }
  }
}
