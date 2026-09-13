import { http } from '@kit.NetworkKit';
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { UserInfo } from './CloudAuthService';

const DOMAIN = 0x0000;
const TAG = 'DreamAuthService';
const BASE_URL = AppConfig.CLOUD_API_BASE_URL;

export interface DreamSessionResult {
  sessionNo: string;
  scene: string;
  qrcode?: string;
}

export interface DreamStatusResult {
  status: number; // 1: 待扫码, 2: 已扫码待确认, 3: 已授权, 4: 已取消, 7: 已过期
  token?: string;  // 授权成功后返回的 App 本地登录 Token
  user?: UserInfo;
}

export interface DreamAuthResponse<T> {
  success: boolean;
  data?: T;
  message?: string;
}

export class DreamAuthService {
  private static instance?: DreamAuthService;
  private readonly MINI_PROGRAM_APPID = 'wx13bc2fcce4f5c8c0';
  private readonly MINI_PROGRAM_PATH = 'pages/index/index';
  // 小程序版本：已上线正式版使用 'release'
  public miniProgramEnvVersion: 'release' | 'trial' | 'develop' = 'release';

  private constructor() {}

  static getInstance(): DreamAuthService {
    if (!DreamAuthService.instance) {
      DreamAuthService.instance = new DreamAuthService();
    }
    return DreamAuthService.instance;
  }

  /**
   * 1. 向 App 自建后端请求创建 DreamAuth 扫码登录会话
   */
  async createSession(): Promise<DreamAuthResponse<DreamSessionResult>> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/auth/wechat/session`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        connectTimeout: 8000,
        readTimeout: 10000
      });

      const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const json = JSON.parse(resStr) as Record<string, Object>;
        if (json.success === true && json.data) {
          return { success: true, data: json.data as DreamSessionResult };
        }
        return { success: false, message: (json.message as string) || '会话创建失败' };
      }
      return { success: false, message: '服务器响应异常' };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'createSession error: %{public}s', JSON.stringify(err));
      return { success: false, message: '网络连接异常，请重试' };
    } finally {
      request.destroy();
    }
  }

  /**
   * 2. 查询会话的授权状态与最终 Token
   * @param sessionNo 会话唯一标识
   */
  async checkStatus(sessionNo: string): Promise<DreamAuthResponse<DreamStatusResult>> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/auth/wechat/session/status?sessionNo=${encodeURIComponent(sessionNo)}`, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json'
        },
        connectTimeout: 5000,
        readTimeout: 8000
      });

      const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode >= 200 && response.responseCode < 300) {
        const json = JSON.parse(resStr) as Record<string, Object>;
        if (json.success === true && json.data) {
          return { success: true, data: json.data as DreamStatusResult };
        }
        return { success: false, message: (json.message as string) || '状态获取失败' };
      }
      return { success: false, message: '状态查询异常' };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'checkStatus error: %{public}s', JSON.stringify(err));
      return { success: false, message: '网络异常' };
    } finally {
      request.destroy();
    }
  }

  /**
   * 3. 拼接明文 URL Scheme 并隐式拉起微信小程序
   * @param context UIAbilityContext 上下文
   * @param scene 获得的唯一场景值参数
   */
  async launchWeChatMiniProgram(context: common.UIAbilityContext, scene: string): Promise<boolean> {
    try {
      const queryStr = `scene=${scene}`;
      const encodedQuery = encodeURIComponent(queryStr);
      const schemeUrl = `weixin://dl/business/?appid=${this.MINI_PROGRAM_APPID}&path=${this.MINI_PROGRAM_PATH}&query=${encodedQuery}&env_version=${this.miniProgramEnvVersion}`;
      hilog.info(DOMAIN, TAG, 'Launching WeChat with scheme: %{public}s', schemeUrl);

      const options: OpenLinkOptions = {
        appLinkingOnly: false
      };
      await context.openLink(schemeUrl, options);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to open link. Code: %{public}d, Message: %{public}s', error.code, error.message);
      return false;
    }
  }

  /**
   * 4. 唤起微信客户端主应用
   * @param context UIAbilityContext 上下文
   */
  async openWeChat(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const options: OpenLinkOptions = {
        appLinkingOnly: false
      };
      await context.openLink('weixin://', options);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to open WeChat. Code: %{public}d, Message: %{public}s', error.code, error.message);
      return false;
    }
  }
}
