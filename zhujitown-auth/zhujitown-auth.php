<?php
/**
 * Plugin Name: ZhuJiTown Auth
 * Plugin URI:  https://www.zhujitown.com
 * Description: 为主机镇 iOS / Android App 提供账号登录与注册接口。仅使用 WordPress 自带的认证 API（wp_authenticate / username_exists / email_exists / wp_insert_user），不引入任何第三方依赖、不建数据库表、不改动用户数据结构。
 * Version:     1.0.0
 * Author:      ZhuJiTown
 * License:     GPLv2 or later
 * Text Domain: zhujitown-auth
 *
 * 路由一览（命名空间 zhujitown/v1）：
 *   POST  /ping                  探测：[200] 插件已启用 / [404] 未安装
 *   POST  /login                 登录（用户名或邮箱 + 密码）
 *   POST  /register              注册（需站点开启「任何人都可以注册」）
 *   POST  /refresh               续期令牌
 *   POST  /logout                注销当前设备令牌
 *   GET   /me                    取当前登录用户信息
 *   POST  /lost-password         找回密码（发重置邮件）
 *   POST  /profile               修改昵称 / 邮箱 / 密码
 *
 * 令牌：HMAC-SHA256 自签名令牌（无状态，不写库），密钥取自 WordPress 自带的 AUTH_SALT，
 *      格式 payload.hmac，payload 为 base64url(JSON{uid,iat,exp,jti,dev})。
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'ZJT_AUTH_VERSION', '1.0.0' );
define( 'ZJT_AUTH_NAMESPACE', 'zhujitown/v1' );
define( 'ZJT_AUTH_TTL', 30 * DAY_IN_SECONDS );

/* -------------------------------------------------------------------------
 * 令牌签发 / 校验
 * ---------------------------------------------------------------------- */

function zjt_auth_secret() {
	// 用 WordPress 自带的盐值派生密钥；站点迁移后令牌会自动失效，这是刻意的安全设计。
	return hash( 'sha256', 'zjt-auth|' . wp_salt( 'auth' ) );
}

function zjt_b64url_encode( $data ) {
	return rtrim( strtr( base64_encode( $data ), '+/', '-_' ), '=' );
}

function zjt_b64url_decode( $data ) {
	$pad = strlen( $data ) % 4;
	if ( $pad ) {
		$data .= str_repeat( '=', 4 - $pad );
	}
	return base64_decode( strtr( $data, '-_', '+/' ) );
}

function zjt_auth_issue_token( $user_id, $device = '' ) {
	$now  = time();
	$payload = array(
		'uid' => (int) $user_id,
		'iat' => $now,
		'exp' => $now + ZJT_AUTH_TTL,
		'jti' => wp_generate_password( 12, false ),
		'dev' => substr( (string) $device, 0, 64 ),
	);
	$body = zjt_b64url_encode( wp_json_encode( $payload ) );
	$sig  = zjt_b64url_encode( hash_hmac( 'sha256', $body, zjt_auth_secret(), true ) );
	return $body . '.' . $sig;
}

/**
 * 解析 Authorization: Bearer <token>，成功返回 WP_User，失败返回 WP_Error。
 */
function zjt_auth_user_from_token( $token ) {
	if ( ! is_string( $token ) || '' === $token || false === strpos( $token, '.' ) ) {
		return new WP_Error( 'zjt_no_token', '缺少访问令牌。', array( 'status' => 401 ) );
	}
	list( $body, $sig ) = explode( '.', $token, 2 );
	$expect = zjt_b64url_encode( hash_hmac( 'sha256', $body, zjt_auth_secret(), true ) );
	if ( ! hash_equals( $expect, $sig ) ) {
		return new WP_Error( 'zjt_bad_token', '令牌无效，请重新登录。', array( 'status' => 401 ) );
	}
	$data = json_decode( zjt_b64url_decode( $body ), true );
	if ( ! is_array( $data ) || empty( $data['uid'] ) ) {
		return new WP_Error( 'zjt_bad_token', '令牌格式错误。', array( 'status' => 401 ) );
	}
	if ( ! empty( $data['exp'] ) && time() > (int) $data['exp'] ) {
		return new WP_Error( 'zjt_token_expired', '登录已过期，请重新登录。', array( 'status' => 401 ) );
	}
	$user = get_userdata( (int) $data['uid'] );
	if ( ! $user || ! $user->exists() ) {
		return new WP_Error( 'zjt_user_gone', '账号不存在或已被删除。', array( 'status' => 401 ) );
	}
	return $user;
}

function zjt_auth_token_from_request( $request ) {
	$header = $request->get_header( 'authorization' );
	if ( $header && preg_match( '/^Bearer\s+(.+)$/i', trim( $header ), $m ) ) {
		return trim( $m[1] );
	}
	$alt = $request->get_header( 'x-zjt-token' );
	if ( $alt ) {
		return trim( $alt );
	}
	$body = $request->get_param( 'token' );
	return is_string( $body ) ? trim( $body ) : '';
}

/* -------------------------------------------------------------------------
 * 输出结构：与 App 端 Model 对齐
 * ---------------------------------------------------------------------- */

function zjt_auth_user_payload( $user, $include_email = true ) {
	$roles = (array) $user->roles;
	$out   = array(
		'id'           => (int) $user->ID,
		'username'     => $user->user_login,
		'display_name' => $user->display_name,
		'slug'         => $user->user_nicename,
		'roles'        => array_values( $roles ),
		'can_manage'   => user_can( $user, 'edit_posts' ),
		'registered'   => mysql_to_rfc3339( $user->user_registered ),
	);
	if ( $include_email ) {
		$out['email'] = $user->user_email;
	}
	$out['avatar'] = array(
		'24'  => get_avatar_url( $user->ID, array( 'size' => 48 ) ),
		'48'  => get_avatar_url( $user->ID, array( 'size' => 96 ) ),
		'96'  => get_avatar_url( $user->ID, array( 'size' => 192 ) ),
	);
	return $out;
}

function zjt_auth_ok( $token, $user ) {
	return new WP_REST_Response(
		array(
			'token'      => $token,
			'expire_at'  => gmdate( 'c', time() + ZJT_AUTH_TTL ),
			'user'       => zjt_auth_user_payload( $user ),
		),
		200
	);
}

function zjt_auth_err( WP_Error $e ) {
	return new WP_REST_Response(
		array(
			'code'    => $e->get_error_code(),
			'message' => $e->get_error_message(),
			'data'    => $e->get_error_data(),
		),
		(int) ( $e->get_error_data()['status'] ?? 400 )
	);
}

/* -------------------------------------------------------------------------
 * 限流：同一 IP 短时间内失败次数过多就拒绝
 * ---------------------------------------------------------------------- */

function zjt_auth_throttle_key( $tag ) {
	return 'zjt_rate_' . $tag . '_' . md5( isset( $_SERVER['REMOTE_ADDR'] ) ? wp_unslash( $_SERVER['REMOTE_ADDR'] ) : 'cli' );
}

function zjt_auth_check_throttle( $tag, $limit = 10, $window = 300 ) {
	$key   = zjt_auth_throttle_key( $tag );
	$tries = (int) get_transient( $key );
	if ( $tries >= $limit ) {
		return new WP_Error( 'zjt_throttled', '尝试过于频繁，请 ' . ceil( $window / 60 ) . ' 分钟后再试。', array( 'status' => 429 ) );
	}
	set_transient( $key, $tries + 1, $window );
	return true;
}

function zjt_auth_clear_throttle( $tag ) {
	delete_transient( zjt_auth_throttle_key( $tag ) );
}

/* -------------------------------------------------------------------------
 * 路由注册
 * ---------------------------------------------------------------------- */

add_action(
	'rest_api_init',
	function () {
		$ns = ZJT_AUTH_NAMESPACE;

		// 探测：App 启动用它判断本插件是否就绪。
		register_rest_route(
			$ns,
			'/ping',
			array(
				'methods'             => 'POST,GET',
				'permission_callback' => '__return_true',
				'callback'            => function () {
					return new WP_REST_Response(
						array(
							'ok'                    => true,
							'plugin'                => 'zhujitown-auth',
							'version'               => ZJT_AUTH_VERSION,
							'ttl'                   => ZJT_AUTH_TTL,
							'registration_open'     => (bool) get_option( 'users_can_register' ),
							'min_password_length'   => 6,
						),
						200
					);
				},
			)
		);

		// 登录
		register_rest_route(
			$ns,
			'/login',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'args'                => array(
					'username' => array( 'required' => true, 'type' => 'string' ),
					'password' => array( 'required' => true, 'type' => 'string' ),
				),
				'callback'            => function ( WP_REST_Request $r ) {
					$lock = zjt_auth_check_throttle( 'login' );
					if ( is_wp_error( $lock ) ) {
						return zjt_auth_err( $lock );
					}
					$login    = trim( (string) $r->get_param( 'username' ) );
					$password = (string) $r->get_param( 'password' );
					$device   = (string) $r->get_param( 'device_id' );

					if ( '' === $login || '' === $password ) {
						return zjt_auth_err( new WP_Error( 'zjt_empty', '用户名和密码不能为空。', array( 'status' => 400 ) ) );
					}

					$user = wp_authenticate( $login, $password );
					if ( is_wp_error( $user ) ) {
						return zjt_auth_err(
							new WP_Error( 'zjt_invalid_credentials', '用户名或密码不正确。', array( 'status' => 401 ) )
						);
					}
					zjt_auth_clear_throttle( 'login' );
					return zjt_auth_ok( zjt_auth_issue_token( $user->ID, $device ), $user );
				},
			)
		);

		// 注册（WordPress 自带开关控制是否开放）
		register_rest_route(
			$ns,
			'/register',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'args'                => array(
					'username' => array( 'required' => true, 'type' => 'string' ),
					'email'    => array( 'required' => true, 'type' => 'string' ),
					'password' => array( 'required' => true, 'type' => 'string' ),
				),
				'callback'            => function ( WP_REST_Request $r ) {
					if ( ! get_option( 'users_can_register' ) ) {
						return zjt_auth_err(
							new WP_Error( 'zjt_register_closed', '本站当前未开放注册，请联系管理员。', array( 'status' => 403 ) )
						);
					}
					$lock = zjt_auth_check_throttle( 'register', 5, 600 );
					if ( is_wp_error( $lock ) ) {
						return zjt_auth_err( $lock );
					}

					$username = sanitize_user( trim( (string) $r->get_param( 'username' ) ), true );
					$email    = sanitize_email( trim( (string) $r->get_param( 'email' ) ) );
					$password = (string) $r->get_param( 'password' );
					$device   = (string) $r->get_param( 'device_id' );

					if ( strlen( $username ) < 3 ) {
						return zjt_auth_err( new WP_Error( 'zjt_bad_username', '用户名至少 3 个字符。', array( 'status' => 400 ) ) );
					}
					if ( ! is_email( $email ) ) {
						return zjt_auth_err( new WP_Error( 'zjt_bad_email', '邮箱格式不正确。', array( 'status' => 400 ) ) );
					}
					if ( strlen( $password ) < 6 ) {
						return zjt_auth_err( new WP_Error( 'zjt_weak_password', '密码至少 6 位。', array( 'status' => 400 ) ) );
					}
					if ( username_exists( $username ) ) {
						return zjt_auth_err( new WP_Error( 'zjt_username_taken', '该用户名已被占用。', array( 'status' => 409 ) ) );
					}
					if ( email_exists( $email ) ) {
						return zjt_auth_err( new WP_Error( 'zjt_email_taken', '该邮箱已注册过，请直接登录。', array( 'status' => 409 ) ) );
					}

					$user_id = wp_insert_user(
						array(
							'user_login'   => $username,
							'user_email'   => $email,
							'user_pass'    => $password,
							'display_name' => $username,
							'role'         => 'subscriber',
						)
					);
					if ( is_wp_error( $user_id ) ) {
						return zjt_auth_err( $user_id );
					}

					wp_new_user_notification( $user_id, null, 'both' );
					zjt_auth_clear_throttle( 'register' );
					return zjt_auth_ok( zjt_auth_issue_token( $user_id, $device ), get_userdata( $user_id ) );
				},
			)
		);

		// 续期
		register_rest_route(
			$ns,
			'/refresh',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'callback'            => function ( WP_REST_Request $r ) {
					$user = zjt_auth_user_from_token( zjt_auth_token_from_request( $r ) );
					if ( is_wp_error( $user ) ) {
						return zjt_auth_err( $user );
					}
					return zjt_auth_ok( zjt_auth_issue_token( $user->ID, (string) $r->get_param( 'device_id' ) ), $user );
				},
			)
		);

		// 获取当前用户
		register_rest_route(
			$ns,
			'/me',
			array(
				'methods'             => 'GET',
				'permission_callback' => '__return_true',
				'callback'            => function ( WP_REST_Request $r ) {
					$user = zjt_auth_user_from_token( zjt_auth_token_from_request( $r ) );
					if ( is_wp_error( $user ) ) {
						return zjt_auth_err( $user );
					}
					return new WP_REST_Response( zjt_auth_user_payload( $user ), 200 );
				},
			)
		);

		// 注销：自签名令牌无法服务端吊销，这里做合法性校验 + 回执，App 端清除本地凭据即可。
		register_rest_route(
			$ns,
			'/logout',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'callback'            => function ( WP_REST_Request $r ) {
					$user = zjt_auth_user_from_token( zjt_auth_token_from_request( $r ) );
					if ( is_wp_error( $user ) ) {
						return zjt_auth_err( $user );
					}
					clean_user_cache( $user->ID );
					return new WP_REST_Response( array( 'ok' => true ), 200 );
				},
			)
		);

		// 找回密码（走 WordPress 自带的取回密码邮件）
		register_rest_route(
			$ns,
			'/lost-password',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'callback'            => function ( WP_REST_Request $r ) {
					$lock = zjt_auth_check_throttle( 'lost', 5, 900 );
					if ( is_wp_error( $lock ) ) {
						return zjt_auth_err( $lock );
					}
					$login = trim( (string) $r->get_param( 'user_login' ) );
					if ( '' === $login ) {
						return zjt_auth_err( new WP_Error( 'zjt_empty', '请填写用户名或邮箱。', array( 'status' => 400 ) ) );
					}
					$res = retrieve_password( $login );
					if ( is_wp_error( $res ) ) {
						return zjt_auth_err( new WP_Error( 'zjt_lost_failed', '无法发送重置邮件，请确认用户名或邮箱是否正确。', array( 'status' => 400 ) ) );
					}
					return new WP_REST_Response( array( 'ok' => true ), 200 );
				},
			)
		);

		// 修改资料
		register_rest_route(
			$ns,
			'/profile',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'callback'            => function ( WP_REST_Request $r ) {
					$user = zjt_auth_user_from_token( zjt_auth_token_from_request( $r ) );
					if ( is_wp_error( $user ) ) {
						return zjt_auth_err( $user );
					}
					$update = array( 'ID' => $user->ID );

					$name = trim( (string) $r->get_param( 'display_name' ) );
					if ( '' !== $name ) {
						$update['display_name'] = $name;
						$update['nickname']     = $name;
					}
					$email = sanitize_email( trim( (string) $r->get_param( 'email' ) ) );
					if ( '' !== $email ) {
						if ( ! is_email( $email ) ) {
							return zjt_auth_err( new WP_Error( 'zjt_bad_email', '邮箱格式不正确。', array( 'status' => 400 ) ) );
						}
						$owner = email_exists( $email );
						if ( $owner && (int) $owner !== (int) $user->ID ) {
							return zjt_auth_err( new WP_Error( 'zjt_email_taken', '该邮箱已被其他账号使用。', array( 'status' => 409 ) ) );
						}
						$update['user_email'] = $email;
					}
					$url = esc_url_raw( trim( (string) $r->get_param( 'url' ) ) );
					if ( '' !== $url ) {
						$update['user_url'] = $url;
					}
					$newpass = (string) $r->get_param( 'new_password' );
					if ( '' !== $newpass ) {
						if ( strlen( $newpass ) < 6 ) {
							return zjt_auth_err( new WP_Error( 'zjt_weak_password', '新密码至少 6 位。', array( 'status' => 400 ) ) );
						}
						$current = zjt_auth_user_from_token( zjt_auth_token_from_request( $r ) );
						if ( ! wp_check_password( (string) $r->get_param( 'current_password' ), $user->user_pass, $user->ID ) ) {
							return zjt_auth_err( new WP_Error( 'zjt_bad_password', '当前密码不正确。', array( 'status' => 403 ) ) );
						}
						$update['user_pass'] = $newpass;
					}

					$res = wp_update_user( $update );
					if ( is_wp_error( $res ) ) {
						return zjt_auth_err( $res );
					}
					return new WP_REST_Response( zjt_auth_user_payload( get_userdata( $user->ID ) ), 200 );
				},
			)
		);
	}
);

/* -------------------------------------------------------------------------
 * CORS：App（尤其调试态）可能从自定义 scheme 发起请求
 * ---------------------------------------------------------------------- */

add_action(
	'rest_api_init',
	function () {
		remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );
		add_filter(
			'rest_pre_serve_request',
			function ( $value ) {
				$origin = isset( $_SERVER['HTTP_ORIGIN'] ) ? wp_unslash( $_SERVER['HTTP_ORIGIN'] ) : '';
				header( 'Access-Control-Allow-Origin: ' . ( $origin ? esc_url_raw( $origin ) : '*' ) );
				header( 'Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE' );
				header( 'Access-Control-Allow-Credentials: true' );
				header( 'Access-Control-Allow-Headers: Authorization, X-ZJT-Token, X-WP-Nonce, Content-Type, Accept' );
				header( 'Access-Control-Expose-Headers: X-WP-Total, X-WP-TotalPages' );
				return $value;
			},
			15
		);
	},
	15
);

// 已登录用户浏览 wp/v2 时，让 Bearer 令牌同样生效。
add_filter(
	'determine_current_user',
	function ( $user_id ) {
		if ( $user_id ) {
			return $user_id;
		}
		if ( ! isset( $_SERVER['HTTP_AUTHORIZATION'] ) ) {
			return $user_id;
		}
		if ( ! preg_match( '/^Bearer\s+(.+)$/i', trim( wp_unslash( $_SERVER['HTTP_AUTHORIZATION'] ) ), $m ) ) {
			return $user_id;
		}
		$user = zjt_auth_user_from_token( trim( $m[1] ) );
		return is_wp_error( $user ) ? $user_id : $user->ID;
	},
	20
);

add_filter(
	'rest_authentication_errors',
	function ( $result ) {
		if ( ! empty( $result ) ) {
			return $result;
		}
		// 允许 App 免 nonce 调用本插件自己的路由。
		$uri = isset( $_SERVER['REQUEST_URI'] ) ? (string) $_SERVER['REQUEST_URI'] : '';
		if ( false !== strpos( $uri, ZJT_AUTH_NAMESPACE ) ) {
			return true;
		}
		// 带 Bearer 令牌访问 wp/v2 时，跳过 cookie nonce 校验。
		if ( ! empty( $_SERVER['HTTP_AUTHORIZATION'] ) && preg_match( '/^Bearer\s+/i', trim( wp_unslash( $_SERVER['HTTP_AUTHORIZATION'] ) ) ) ) {
			$token = preg_replace( '/^Bearer\s+/i', '', trim( wp_unslash( $_SERVER['HTTP_AUTHORIZATION'] ) ) );
			if ( ! is_wp_error( zjt_auth_user_from_token( $token ) ) ) {
				return true;
			}
		}
		return $result;
	},
	20
);
