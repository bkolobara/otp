%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2019. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%

-module(ssl_basic_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("public_key/include/public_key.hrl").

-include("ssl_api.hrl").
-include("ssl_cipher.hrl").
-include("ssl_internal.hrl").
-include("ssl_alert.hrl").
-include("ssl_internal.hrl").
-include("tls_record.hrl").
-include("tls_handshake.hrl").

-define(TIMEOUT, 20000).
-define(EXPIRE, 10).
-define(SLEEP, 500).
-define(RENEGOTIATION_DISABLE_TIME, 12000).
-define(CLEAN_SESSION_DB, 60000).
-define(SEC_RENEGOTIATION_TIMEOUT, 30).

%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------
all() -> 
    [
     {group, basic},
     {group, basic_tls},
     {group, options},
     {group, options_tls},
     {group, 'dtlsv1.2'},
     {group, 'dtlsv1'},
     %%{group, 'tlsv1.3'},
     {group, 'tlsv1.2'},
     {group, 'tlsv1.1'},
     {group, 'tlsv1'},
     {group, 'sslv3'}
    ].

groups() ->
    [{basic, [], basic_tests()},
     {basic_tls, [], basic_tests_tls()},
     {options, [], options_tests()},
     {options_tls, [], options_tests_tls()},
     {'dtlsv1.2', [], all_versions_groups()},
     {'dtlsv1', [], all_versions_groups()},
     {'tlsv1.2', [], all_versions_groups() ++ tls_versions_groups() ++ [conf_signature_algs, no_common_signature_algs]},
     {'tlsv1.1', [], all_versions_groups() ++ tls_versions_groups()},
     {'tlsv1', [], all_versions_groups() ++ tls_versions_groups() ++ rizzo_tests()},
     {'sslv3', [], all_versions_groups() ++ tls_versions_groups() ++ rizzo_tests() -- [tls_ciphersuite_vs_version]},
     {api,[], api_tests()},
     {api_tls,[], api_tests_tls()},
     {ciphers, [], cipher_tests()},
     {error_handling_tests, [], error_handling_tests()},
     {error_handling_tests_tls, [], error_handling_tests_tls()}
    ].

tls_versions_groups ()->
    [
     {group, api_tls},
     {group, error_handling_tests_tls}].

all_versions_groups ()->
    [{group, api},
     {group, ciphers},
     {group, error_handling_tests}].


basic_tests() ->
    [app,
     appup,
     alerts,
     alert_details,
     alert_details_not_too_big,
     version_option,
     connect_twice,
     connect_dist,
     clear_pem_cache,
     defaults,
     fallback,
     cipher_format
    ].

basic_tests_tls() ->
    [tls_send_close
    ].

options_tests() ->
    [
     %%der_input, Move/remove as redundent
     ssl_options_not_proplist,
     raw_ssl_option,
     invalid_inet_get_option,
     invalid_inet_get_option_not_list,
     invalid_inet_get_option_improper_list,
     invalid_inet_set_option,
     invalid_inet_set_option_not_list,
     invalid_inet_set_option_improper_list,
     invalid_options,
     protocol_versions,
     empty_protocol_versions,
     ipv6,
     reuseaddr,
     unordered_protocol_versions_server,
     unordered_protocol_versions_client,
     max_handshake_size
].

options_tests_tls() ->
    [tls_misc_ssl_options,
     tls_tcp_reuseaddr].

api_tests() ->
    [eccs,
     getstat,
     accept_pool,
     socket_options,
     internal_active_1,
     cipher_suites
    ].

api_tests_tls() ->
    [tls_versions_option,
     tls_socket_options,
     new_options_in_accept
    ].

cipher_tests() ->
    [old_cipher_suites,
     cipher_suites_mix,     
     default_reject_anonymous].

error_handling_tests()->
    [
    ].

error_handling_tests_tls()->
    [
    ].

rizzo_tests() ->
    [rizzo,
     no_rizzo_rc4,
     rizzo_one_n_minus_one,
     rizzo_zero_n,
     rizzo_disabled].


%%--------------------------------------------------------------------
init_per_suite(Config0) ->
    catch crypto:stop(),
    try crypto:start() of
	ok ->
	    ssl_test_lib:clean_start(),
	    %% make rsa certs using oppenssl
	    {ok, _} = make_certs:all(proplists:get_value(data_dir, Config0),
				     proplists:get_value(priv_dir, Config0)),
	    Config1 = ssl_test_lib:make_dsa_cert(Config0),
	    Config2 = ssl_test_lib:make_ecdsa_cert(Config1),
            Config3 = ssl_test_lib:make_rsa_cert(Config2),
	    Config = ssl_test_lib:make_ecdh_rsa_cert(Config3),
	    ssl_test_lib:cert_options(Config)
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    ssl:stop(),
    application:stop(crypto).

%%--------------------------------------------------------------------

init_per_group(GroupName, Config) when GroupName == basic_tls;
                                       GroupName == options_tls;
                                       GroupName == options;
                                       GroupName == basic;
                                       GroupName == session;
                                       GroupName == error_handling_tests_tls ->
    ssl_test_lib:clean_tls_version(Config);
%% Do not automatically configure TLS version for the 'tlsv1.3' group
init_per_group('tlsv1.3' = GroupName, Config) ->
    case ssl_test_lib:sufficient_crypto_support(GroupName) of
        true ->
            ssl:start(),
            Config;
        false ->
            {skip, "Missing crypto support"}
    end;
init_per_group(GroupName, Config) ->
    ssl_test_lib:clean_tls_version(Config),                          
    case ssl_test_lib:is_tls_version(GroupName) andalso ssl_test_lib:sufficient_crypto_support(GroupName) of
	true ->
	    ssl_test_lib:init_tls_version(GroupName, Config);
	_ ->
	    case ssl_test_lib:sufficient_crypto_support(GroupName) of
		true ->
		    ssl:start(),
		    Config;
		false ->
		    {skip, "Missing crypto support"}
	    end
    end.

end_per_group(GroupName, Config) ->
  case ssl_test_lib:is_tls_version(GroupName) of
      true ->
          ssl_test_lib:clean_tls_version(Config);
      false ->
          Config
  end.

%%--------------------------------------------------------------------
init_per_testcase(Case, Config) when Case ==  unordered_protocol_versions_client;
				     Case == unordered_protocol_versions_server->
    case proplists:get_value(supported, ssl:versions()) of
	['tlsv1.2' | _] ->
	    ct:timetrap({seconds, 5}),
	    Config;
	_ ->
	    {skip, "TLS 1.2 need but not supported on this platform"}
    end;

init_per_testcase(protocol_versions, Config)  ->
    ssl:stop(),
    application:load(ssl),
    %% For backwards compatibility sslv2 should be filtered out.
    application:set_env(ssl, protocol_version, [sslv2, sslv3, tlsv1]),
    ssl:start(),
    ct:timetrap({seconds, 5}),
    Config;

init_per_testcase(empty_protocol_versions, Config)  ->
    ssl:stop(),
    application:load(ssl),
    ssl_test_lib:clean_env(),
    application:set_env(ssl, protocol_version, []),
    ssl:start(),
    ct:timetrap({seconds, 5}),
    Config;

init_per_testcase(fallback, Config)  ->
    case tls_record:highest_protocol_version([]) of
	{3, N} when N > 1 ->
	    ct:timetrap({seconds, 5}),
	    Config;
	_ ->
	    {skip, "Not relevant if highest supported version is less than 3.2"}
    end;

init_per_testcase(TestCase, Config) when TestCase == versions_option;
					 TestCase == tls_tcp_connect_big ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 60}),
    Config;

init_per_testcase(version_option, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 10}),
    Config;

init_per_testcase(reuse_session, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 10}),
    Config;

init_per_testcase(rizzo, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 60}),
    Config;

init_per_testcase(no_rizzo_rc4, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 60}),
    Config;

init_per_testcase(rizzo_one_n_minus_one, Config) ->
    ct:log("TLS/SSL version ~p~n ", [tls_record:supported_protocol_versions()]),
    ct:timetrap({seconds, 60}),
    rizzo_add_mitigation_option(one_n_minus_one, Config);

init_per_testcase(rizzo_zero_n, Config) ->
    ct:log("TLS/SSL version ~p~n ", [tls_record:supported_protocol_versions()]),
    ct:timetrap({seconds, 60}),
    rizzo_add_mitigation_option(zero_n, Config);

init_per_testcase(rizzo_disabled, Config) ->
    ct:log("TLS/SSL version ~p~n ", [tls_record:supported_protocol_versions()]),
    ct:timetrap({seconds, 60}),
    rizzo_add_mitigation_option(disabled, Config);

init_per_testcase(TestCase, Config) when TestCase == clear_pem_cache;
						TestCase == der_input;
						TestCase == defaults ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    %% White box test need clean start
    ssl:stop(),
    ssl:start(),
    ct:timetrap({seconds, 20}),
    Config;
init_per_testcase(raw_ssl_option, Config) ->
    ct:timetrap({seconds, 5}),
    case os:type() of
        {unix,linux} ->
            Config;
        _ ->
            {skip, "Raw options are platform-specific"}
    end;

init_per_testcase(accept_pool, Config) ->
    ct:timetrap({seconds, 5}),
    case proplists:get_value(protocol, Config) of
	dtls ->
            {skip, "Not yet supported on DTLS sockets"};
	_ ->
	    ssl_test_lib:ct_log_supported_protocol_versions(Config),
	    Config
    end;

init_per_testcase(internal_active_1, Config) ->
    ssl:stop(),
    application:load(ssl),
    application:set_env(ssl, internal_active_n, 1),
    ssl:start(),
    ct:timetrap({seconds, 5}),
    Config;

init_per_testcase(eccs, Config) ->
    case ssl:eccs() of
        [] ->
            {skip, "named curves not supported"};
        [_|_] ->
            ssl_test_lib:ct_log_supported_protocol_versions(Config),
            ct:timetrap({seconds, 5}),
            Config
    end;
init_per_testcase(_TestCase, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 5}),
    Config.

end_per_testcase(reuse_session_expired, Config) ->
    application:unset_env(ssl, session_lifetime),
    application:unset_env(ssl, session_delay_cleanup_time),
    end_per_testcase(default_action, Config);

end_per_testcase(internal_active_n, Config) ->
    application:unset_env(ssl, internal_active_n),
    end_per_testcase(default_action, Config);

end_per_testcase(Case, Config) when Case == protocol_versions;
				    Case == empty_protocol_versions->
    application:unset_env(ssl, protocol_versions),
    end_per_testcase(default_action, Config);

end_per_testcase(_TestCase, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------
app() ->
    [{doc, "Test that the ssl app file is ok"}].
app(Config) when is_list(Config) ->
    ok = ?t:app_test(ssl).
%%--------------------------------------------------------------------
appup() ->
    [{doc, "Test that the ssl appup file is ok"}].
appup(Config) when is_list(Config) ->
    ok = ?t:appup_test(ssl).
%%--------------------------------------------------------------------
alerts() ->
    [{doc, "Test ssl_alert:alert_txt/1"}].
alerts(Config) when is_list(Config) ->
    Descriptions = [?CLOSE_NOTIFY, ?UNEXPECTED_MESSAGE, ?BAD_RECORD_MAC,
		    ?DECRYPTION_FAILED_RESERVED, ?RECORD_OVERFLOW, ?DECOMPRESSION_FAILURE,
		    ?HANDSHAKE_FAILURE, ?BAD_CERTIFICATE, ?UNSUPPORTED_CERTIFICATE,
		    ?CERTIFICATE_REVOKED,?CERTIFICATE_EXPIRED, ?CERTIFICATE_UNKNOWN,
		    ?ILLEGAL_PARAMETER, ?UNKNOWN_CA, ?ACCESS_DENIED, ?DECODE_ERROR,
		    ?DECRYPT_ERROR, ?EXPORT_RESTRICTION, ?PROTOCOL_VERSION, 
		    ?INSUFFICIENT_SECURITY, ?INTERNAL_ERROR, ?USER_CANCELED,
		    ?NO_RENEGOTIATION, ?UNSUPPORTED_EXTENSION, ?CERTIFICATE_UNOBTAINABLE,
		    ?UNRECOGNISED_NAME, ?BAD_CERTIFICATE_STATUS_RESPONSE,
		    ?BAD_CERTIFICATE_HASH_VALUE, ?UNKNOWN_PSK_IDENTITY, 
		    255 %% Unsupported/unknow alert will result in a description too
		   ],
    Alerts = [?ALERT_REC(?WARNING, ?CLOSE_NOTIFY) | 
	      [?ALERT_REC(?FATAL, Desc) || Desc <- Descriptions]],
    lists:foreach(fun(Alert) ->
                          try ssl_alert:alert_txt(Alert)
                          catch
			    C:E:T ->
                                  ct:fail({unexpected, {C, E, T}})
			end 
		  end, Alerts).
%%--------------------------------------------------------------------
alert_details() ->
    [{doc, "Test that ssl_alert:alert_txt/1 result contains extendend error description"}].
alert_details(Config) when is_list(Config) ->
    Unique = make_ref(),
    UniqueStr = lists:flatten(io_lib:format("~w", [Unique])),
    Alert = ?ALERT_REC(?WARNING, ?CLOSE_NOTIFY, Unique),
    case string:str(ssl_alert:alert_txt(Alert), UniqueStr) of
        0 ->
            ct:fail(error_details_missing);
        _ ->
            ok
    end.

%%--------------------------------------------------------------------
alert_details_not_too_big() ->
    [{doc, "Test that ssl_alert:alert_txt/1 limits printed depth of extended error description"}].
alert_details_not_too_big(Config) when is_list(Config) ->
    Reason = lists:duplicate(10, lists:duplicate(10, lists:duplicate(10, {some, data}))),
    Alert = ?ALERT_REC(?WARNING, ?CLOSE_NOTIFY, Reason),
    case length(ssl_alert:alert_txt(Alert)) < 1000 of
        true ->
            ok;
        false ->
            ct:fail(ssl_alert_text_too_big)
    end.

%%--------------------------------------------------------------------
new_options_in_accept() ->
    [{doc,"Test that you can set ssl options in ssl_accept/3 and not only in tcp upgrade"}].
new_options_in_accept(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts0 = ssl_test_lib:ssl_options(server_dsa_opts, Config),
    [_ , _ | ServerSslOpts] = ssl_test_lib:ssl_options(server_opts, Config), %% Remove non ssl opts
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Version = ssl_test_lib:protocol_options(Config, [{tls, sslv3}, {dtls, dtlsv1}]),
    Cipher = ssl_test_lib:protocol_options(Config, [{tls, #{key_exchange =>rsa,
                                                            cipher => rc4_128,
                                                            mac => sha,
                                                            prf => default_prf
                                                           }}, 
                                                    {dtls, #{key_exchange =>rsa,
                                                             cipher => aes_128_cbc,
                                                             mac => sha,
                                                             prf => default_prf
                                                            }}]),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{ssl_extra_opts, [{versions, [Version]},
							  {ciphers,[Cipher]} | ServerSslOpts]}, %% To be set in ssl_accept/3
					{mfa, {?MODULE, connection_info_result, []}},
					{options, proplists:delete(cacertfile, ServerOpts0)}]),
    
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, connection_info_result, []}},
					{options, [{versions, [Version]},
						   {ciphers,[Cipher]} | ClientOpts]}]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ServerMsg = ClientMsg = {ok, {Version, Cipher}},
   
    ssl_test_lib:check_result(Server, ServerMsg, Client, ClientMsg),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
protocol_versions() ->
    [{doc,"Test to set a list of protocol versions in app environment."}].

protocol_versions(Config) when is_list(Config) -> 
    basic_test(Config).

%%--------------------------------------------------------------------
empty_protocol_versions() ->
    [{doc,"Test to set an empty list of protocol versions in app environment."}].

empty_protocol_versions(Config) when is_list(Config) -> 
    basic_test(Config).


%%--------------------------------------------------------------------
getstat() ->
    [{doc,"Test API function getstat/2"}].

getstat(Config) when is_list(Config) ->
    ClientOpts = ?config(client_opts, Config),
    ServerOpts = ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server1 =
        ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                                   {from, self()},
                                   {mfa, {ssl_test_lib, send_recv_result, []}},
                                   {options,  [{active, false} | ServerOpts]}]),
    Port1 = ssl_test_lib:inet_port(Server1),
    Server2 =
        ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                                   {from, self()},
                                   {mfa, {ssl_test_lib, send_recv_result, []}},
                                   {options,  [{active, false} | ServerOpts]}]),
    Port2 = ssl_test_lib:inet_port(Server2),
    {ok, ActiveC} = rpc:call(ClientNode, ssl, connect,
                          [Hostname,Port1,[{active, once}|ClientOpts]]),
    {ok, PassiveC} = rpc:call(ClientNode, ssl, connect,
                          [Hostname,Port2,[{active, false}|ClientOpts]]),

    ct:log("Testcase ~p, Client ~p  Servers ~p, ~p ~n",
                       [self(), self(), Server1, Server2]),

    %% We only check that the values are non-zero initially
    %% (due to the handshake), and that sending more changes the values.

    %% Passive socket.

    {ok, InitialStats} = ssl:getstat(PassiveC),
    ct:pal("InitialStats  ~p~n", [InitialStats]),
    [true] = lists:usort([0 =/= proplists:get_value(Name, InitialStats)
        || Name <- [recv_cnt, recv_oct, recv_avg, recv_max, send_cnt, send_oct, send_avg, send_max]]),

    ok = ssl:send(PassiveC, "Hello world"),
    wait_for_send(PassiveC),
    {ok, SStats} = ssl:getstat(PassiveC, [send_cnt, send_oct]),
    ct:pal("SStats  ~p~n", [SStats]),
    [true] = lists:usort([proplists:get_value(Name, SStats) =/= proplists:get_value(Name, InitialStats)
        || Name <- [send_cnt, send_oct]]),

    %% Active socket.

    {ok, InitialAStats} = ssl:getstat(ActiveC),
    ct:pal("InitialAStats  ~p~n", [InitialAStats]),
    [true] = lists:usort([0 =/= proplists:get_value(Name, InitialAStats)
        || Name <- [recv_cnt, recv_oct, recv_avg, recv_max, send_cnt, send_oct, send_avg, send_max]]),

    _ = receive
        {ssl, ActiveC, _} ->
            ok
    after
        ?SLEEP ->
            exit(timeout)
    end,

    ok = ssl:send(ActiveC, "Hello world"),
    wait_for_send(ActiveC),
    {ok, ASStats} = ssl:getstat(ActiveC, [send_cnt, send_oct]),
    ct:pal("ASStats  ~p~n", [ASStats]),
    [true] = lists:usort([proplists:get_value(Name, ASStats) =/= proplists:get_value(Name, InitialAStats)
        || Name <- [send_cnt, send_oct]]),

    ok.





%%--------------------------------------------------------------------
connect_dist() ->
    [{doc,"Test a simple connect as is used by distribution"}].

connect_dist(Config) when is_list(Config) -> 
    ClientOpts0 = ssl_test_lib:ssl_options(client_kc_opts, Config),
    ClientOpts = [{ssl_imp, new},{active, false}, {packet,4}|ClientOpts0],
    ServerOpts0 = ssl_test_lib:ssl_options(server_kc_opts, Config),
    ServerOpts = [{ssl_imp, new},{active, false}, {packet,4}|ServerOpts0],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, connect_dist_s, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, connect_dist_c, []}},
					{options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------

clear_pem_cache() ->
    [{doc,"Test that internal reference tabel is cleaned properly even when "
     " the PEM cache is cleared" }].
clear_pem_cache(Config) when is_list(Config) -> 
    {status, _, _, StatusInfo} = sys:get_status(whereis(ssl_manager)),
    [_, _,_, _, Prop] = StatusInfo,
    State = ssl_test_lib:state(Prop),
    [_,{FilRefDb, _} |_] = element(6, State),
    {Server, Client} = basic_verify_test_no_close(Config),
    CountReferencedFiles = fun({_, -1}, Acc) ->
				   Acc;
			      ({_, N}, Acc) ->
				   N + Acc
			   end,
    
    2 = ets:foldl(CountReferencedFiles, 0, FilRefDb), 
    ssl:clear_pem_cache(),
    _ = sys:get_status(whereis(ssl_manager)),
    {Server1, Client1} = basic_verify_test_no_close(Config),
    4 =  ets:foldl(CountReferencedFiles, 0, FilRefDb), 
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    ct:sleep(2000),
    _ = sys:get_status(whereis(ssl_manager)),
    2 =  ets:foldl(CountReferencedFiles, 0, FilRefDb), 
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client1),
    ct:sleep(2000),
    _ = sys:get_status(whereis(ssl_manager)),
    0 =  ets:foldl(CountReferencedFiles, 0, FilRefDb).

%%--------------------------------------------------------------------

fallback() ->
    [{doc, "Test TLS_FALLBACK_SCSV downgrade prevention"}].

fallback(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    
    Server = 
	ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0}, 
					 {from, self()},
					 {options, ServerOpts}]),
    
    Port = ssl_test_lib:inet_port(Server),
    
    Client = 
        ssl_test_lib:start_client_error([{node, ClientNode},
                                         {port, Port}, {host, Hostname},
                                         {from, self()},  {options,
                                                           [{fallback, true},
                                                            {versions, ['tlsv1']}
                                                            | ClientOpts]}]),
    ssl_test_lib:check_server_alert(Server, Client, inappropriate_fallback).
   

%%--------------------------------------------------------------------
cipher_format() ->
    [{doc, "Test that cipher conversion from maps | tuples | stings to binarys works"}].
cipher_format(Config) when is_list(Config) ->
    {ok, Socket0} = ssl:listen(0, [{ciphers, ssl:cipher_suites(default, 'tlsv1.2')}]),
    ssl:close(Socket0),
    %% Legacy
    {ok, Socket1} = ssl:listen(0, [{ciphers, ssl:cipher_suites()}]),
    ssl:close(Socket1),
    {ok, Socket2} = ssl:listen(0, [{ciphers, ssl:cipher_suites(openssl)}]),
    ssl:close(Socket2).

%%--------------------------------------------------------------------

cipher_suites() ->
    [{doc,"Test API function cipher_suites/2, filter_cipher_suites/2"
      " and prepend|append_cipher_suites/2"}].

cipher_suites(Config) when is_list(Config) -> 
    MandatoryCipherSuiteTLS1_0TLS1_1 = #{key_exchange => rsa,
                                         cipher => '3des_ede_cbc',
                                         mac => sha,
                                         prf => default_prf},
    MandatoryCipherSuiteTLS1_0TLS1_2 = #{key_exchange =>rsa,
                                         cipher => 'aes_128_cbc',
                                         mac => sha,
                                         prf => default_prf}, 
    Version = ssl_test_lib:protocol_version(Config),
    All = [_|_] = ssl:cipher_suites(all, Version),
    Default = [_|_] = ssl:cipher_suites(default, Version),
    Anonymous = [_|_] = ssl:cipher_suites(anonymous, Version),
    true = length(Default) < length(All),
    Filters = [{key_exchange, 
                fun(dhe_rsa) -> 
                        true;
                   (_) -> 
                        false
                end
               }, 
               {cipher, 
                fun(aes_256_cbc) ->
                        true;
                   (_) -> 
                        false
                end
               },
               {mac, 
                fun(sha) ->
                        true;
                   (_) -> 
                        false
                end
               }
              ],
    Cipher = #{cipher => aes_256_cbc,
               key_exchange => dhe_rsa,
               mac => sha,
               prf => default_prf},
    [Cipher] = ssl:filter_cipher_suites(All, Filters),    
    [Cipher | Rest0] = ssl:prepend_cipher_suites([Cipher], Default),
    [Cipher | Rest0] = ssl:prepend_cipher_suites(Filters, Default),
    true = lists:member(Cipher, Default), 
    false = lists:member(Cipher, Rest0), 
    [Cipher | Rest1] = lists:reverse(ssl:append_cipher_suites([Cipher], Default)),
    [Cipher | Rest1] = lists:reverse(ssl:append_cipher_suites(Filters, Default)),
    true = lists:member(Cipher, Default),
    false = lists:member(Cipher, Rest1),
    [] = lists:dropwhile(fun(X) -> not lists:member(X, Default) end, Anonymous),
    [] = lists:dropwhile(fun(X) -> not lists:member(X, All) end, Anonymous),        
    true = lists:member(MandatoryCipherSuiteTLS1_0TLS1_1, All),
    true = lists:member(MandatoryCipherSuiteTLS1_0TLS1_2, All).

%%--------------------------------------------------------------------

old_cipher_suites() ->
    [{doc,"Test API function cipher_suites/0"}].

old_cipher_suites(Config) when is_list(Config) -> 
    MandatoryCipherSuite = {rsa, '3des_ede_cbc', sha},
    [_|_] = Suites = ssl:cipher_suites(),
    Suites = ssl:cipher_suites(erlang),
    [_|_] = ssl:cipher_suites(openssl),
    true = lists:member(MandatoryCipherSuite,  ssl:cipher_suites(all)).

%%--------------------------------------------------------------------
cipher_suites_mix() ->
    [{doc,"Test to have old and new cipher suites at the same time"}].

cipher_suites_mix(Config) when is_list(Config) -> 
    CipherSuites = [{dhe_rsa,aes_128_cbc,sha256,sha256}, {dhe_rsa,aes_128_cbc,sha}],
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, [{ciphers, CipherSuites} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).
%%--------------------------------------------------------------------
tls_socket_options() ->
    [{doc,"Test API function getopts/2 and setopts/2"}].

tls_socket_options(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Values = [{mode, list}, {packet, 0}, {header, 0},
		      {active, true}],    
    %% Shall be the reverse order of Values! 
    Options = [active, header, packet, mode],
    
    NewValues = [{mode, binary}, {active, once}],
    %% Shall be the reverse order of NewValues! 
    NewOptions = [active, mode],
    
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
			   {mfa, {?MODULE, tls_socket_options_result, 
				  [Options, Values, NewOptions, NewValues]}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
			   {from, self()}, 
			   {mfa, {?MODULE, tls_socket_options_result, 
				  [Options, Values, NewOptions, NewValues]}},
			   {options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    
    {ok, Listen} = ssl:listen(0, ServerOpts),
    {ok,[{mode,list}]} = ssl:getopts(Listen, [mode]),
    ok = ssl:setopts(Listen, [{mode, binary}]),
    {ok,[{mode, binary}]} = ssl:getopts(Listen, [mode]),
    {ok,[{recbuf, _}]} = ssl:getopts(Listen, [recbuf]),
    ssl:close(Listen).

tls_socket_options_result(Socket, Options, DefaultValues, NewOptions, NewValues) ->
    %% Test get/set emulated opts
    {ok, DefaultValues} = ssl:getopts(Socket, Options), 
    ssl:setopts(Socket, NewValues),
    {ok, NewValues} = ssl:getopts(Socket, NewOptions),
    %% Test get/set inet opts
    {ok,[{nodelay,false}]} = ssl:getopts(Socket, [nodelay]),  
    ssl:setopts(Socket, [{nodelay, true}]),
    {ok,[{nodelay, true}]} = ssl:getopts(Socket, [nodelay]),
    {ok, All} = ssl:getopts(Socket, []),
    ct:log("All opts ~p~n", [All]),
    ok.


%%--------------------------------------------------------------------
socket_options() ->
    [{doc,"Test API function getopts/2 and setopts/2"}].

socket_options(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Values = [{mode, list}, {active, true}],    
    %% Shall be the reverse order of Values! 
    Options = [active, mode],
    
    NewValues = [{mode, binary}, {active, once}],
    %% Shall be the reverse order of NewValues! 
    NewOptions = [active, mode],
    
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
			   {mfa, {?MODULE, socket_options_result, 
				  [Options, Values, NewOptions, NewValues]}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
			   {from, self()}, 
			   {mfa, {?MODULE, socket_options_result, 
				  [Options, Values, NewOptions, NewValues]}},
			   {options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    
    {ok, Listen} = ssl:listen(0, ServerOpts),
    {ok,[{mode,list}]} = ssl:getopts(Listen, [mode]),
    ok = ssl:setopts(Listen, [{mode, binary}]),
    {ok,[{mode, binary}]} = ssl:getopts(Listen, [mode]),
    {ok,[{recbuf, _}]} = ssl:getopts(Listen, [recbuf]),
    ssl:close(Listen).


socket_options_result(Socket, Options, DefaultValues, NewOptions, NewValues) ->
    %% Test get/set emulated opts
    {ok, DefaultValues} = ssl:getopts(Socket, Options), 
    ssl:setopts(Socket, NewValues),
    {ok, NewValues} = ssl:getopts(Socket, NewOptions),
    %% Test get/set inet opts
    {ok,[{reuseaddr, _}]} = ssl:getopts(Socket, [reuseaddr]),  
    {ok, All} = ssl:getopts(Socket, []),
    ct:log("All opts ~p~n", [All]),
    ok.


%%--------------------------------------------------------------------
invalid_inet_get_option() ->
    [{doc,"Test handling of invalid inet options in getopts"}].

invalid_inet_get_option(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, get_invalid_inet_option, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
invalid_inet_get_option_not_list() ->
    [{doc,"Test handling of invalid type in getopts"}].

invalid_inet_get_option_not_list(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, get_invalid_inet_option_not_list, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


get_invalid_inet_option_not_list(Socket) ->
    {error, {options, {socket_options, some_invalid_atom_here}}}
     = ssl:getopts(Socket, some_invalid_atom_here),
     ok.

%%--------------------------------------------------------------------
invalid_inet_get_option_improper_list() ->
    [{doc,"Test handling of invalid type in getopts"}].

invalid_inet_get_option_improper_list(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, get_invalid_inet_option_improper_list, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


get_invalid_inet_option_improper_list(Socket) ->
    {error, {options, {socket_options, foo,_}}} = ssl:getopts(Socket, [packet | foo]),
    ok.

%%--------------------------------------------------------------------
invalid_inet_set_option() ->
    [{doc,"Test handling of invalid inet options in setopts"}].

invalid_inet_set_option(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, set_invalid_inet_option, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

set_invalid_inet_option(Socket) ->
    {error, {options, {socket_options, {packet, foo}}}} = ssl:setopts(Socket, [{packet, foo}]),
    {error, {options, {socket_options, {header, foo}}}} = ssl:setopts(Socket, [{header, foo}]),
    {error, {options, {socket_options, {active, foo}}}} = ssl:setopts(Socket, [{active, foo}]),
    {error, {options, {socket_options, {mode, foo}}}}   = ssl:setopts(Socket, [{mode, foo}]),
    ok.
%%--------------------------------------------------------------------
invalid_inet_set_option_not_list() ->
    [{doc,"Test handling of invalid type in setopts"}].

invalid_inet_set_option_not_list(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, set_invalid_inet_option_not_list, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


set_invalid_inet_option_not_list(Socket) ->
    {error, {options, {not_a_proplist, some_invalid_atom_here}}}
	= ssl:setopts(Socket, some_invalid_atom_here),
    ok.

%%--------------------------------------------------------------------
invalid_inet_set_option_improper_list() ->
    [{doc,"Test handling of invalid tye in setopts"}].

invalid_inet_set_option_improper_list(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {?MODULE, set_invalid_inet_option_improper_list, []}},
			   {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, no_result, []}},
			   {options, ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

set_invalid_inet_option_improper_list(Socket) ->
    {error, {options, {not_a_proplist, [{packet, 0} | {foo, 2}]}}} =
	ssl:setopts(Socket, [{packet, 0} | {foo, 2}]),
    ok.

%%--------------------------------------------------------------------
tls_misc_ssl_options() ->
    [{doc,"Test what happens when we give valid options"}].

tls_misc_ssl_options(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    
    %% Check that ssl options not tested elsewhere are filtered away e.i. not passed to inet.
    TestOpts = [{depth, 1}, 
		{key, undefined}, 
		{password, []},
		{reuse_session, fun(_,_,_,_) -> true end},
		{cb_info, {gen_tcp, tcp, tcp_closed, tcp_error}}],
    
   Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result_active, []}},
				   {options,  TestOpts ++ ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result_active, []}},
				   {options, TestOpts ++ ClientOpts}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			 [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
ssl_options_not_proplist() ->
    [{doc,"Test what happens if an option is not a key value tuple"}].

ssl_options_not_proplist(Config) when is_list(Config) ->
    BadOption =  {client_preferred_next_protocols, 
		  client, [<<"spdy/3">>,<<"http/1.1">>], <<"http/1.1">>},
    {option_not_a_key_value_tuple, BadOption} =
	ssl:connect("twitter.com", 443, [binary, {active, false}, 
					 BadOption]).

%%--------------------------------------------------------------------
raw_ssl_option() ->
    [{doc,"Ensure that a single 'raw' option is passed to ssl:listen correctly."}].

raw_ssl_option(Config) when is_list(Config) ->
    % 'raw' option values are platform-specific; these are the Linux values:
    IpProtoTcp = 6,
    % Use TCP_KEEPIDLE, because (e.g.) TCP_MAXSEG can't be read back reliably.
    TcpKeepIdle = 4,
    KeepAliveTimeSecs = 55,
    LOptions = [{raw, IpProtoTcp, TcpKeepIdle, <<KeepAliveTimeSecs:32/native>>}],
    {ok, LSocket} = ssl:listen(0, LOptions),
    % Per http://www.erlang.org/doc/man/inet.html#getopts-2, we have to specify
    % exactly which raw option we want, and the size of the buffer.
    {ok, [{raw, IpProtoTcp, TcpKeepIdle, <<KeepAliveTimeSecs:32/native>>}]} = ssl:getopts(LSocket, [{raw, IpProtoTcp, TcpKeepIdle, 4}]).


%%--------------------------------------------------------------------
eccs() ->
    [{doc, "Test API functions eccs/0 and eccs/1"}].

eccs(Config) when is_list(Config) ->
    [_|_] = All = ssl:eccs(),
    [] = ssl:eccs(sslv3),
    [_|_] = Tls = ssl:eccs(tlsv1),
    [_|_] = Tls1 = ssl:eccs('tlsv1.1'),
    [_|_] = Tls2 = ssl:eccs('tlsv1.2'),
    [_|_] = Tls1 = ssl:eccs('dtlsv1'),
    [_|_] = Tls2 = ssl:eccs('dtlsv1.2'),
    %% ordering is currently not verified by the test
    true = lists:sort(All) =:= lists:usort(Tls ++ Tls1 ++ Tls2),
    ok.

%%--------------------------------------------------------------------
send_recv() ->
    [{doc,""}].
send_recv(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{active, false} | ClientOpts]}]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			 [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
tls_send_close() ->
    [{doc,""}].
tls_send_close(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    {ok, TcpS} = rpc:call(ClientNode, gen_tcp, connect, 
			  [Hostname,Port,[binary, {active, false}]]),
    {ok, SslS} = rpc:call(ClientNode, ssl, connect, 
			  [TcpS,[{active, false}|ClientOpts]]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
		       [self(), self(), Server]),
    ok = ssl:send(SslS, "Hello world"),      
    {ok,<<"Hello world">>} = ssl:recv(SslS, 11),    
    gen_tcp:close(TcpS),    
    {error, _} = ssl:send(SslS, "Hello world").

%%--------------------------------------------------------------------
version_option() ->
    [{doc, "Use version option and do no specify ciphers list. Bug specified incorrect ciphers"}].
version_option(Config) when is_list(Config) ->
    Versions = proplists:get_value(supported, ssl:versions()),
    [version_option_test(Config, Version) || Version <- Versions].
   

internal_active_1() ->
    [{doc,"Test internal active 1 (behave as internal active once)"}].

internal_active_1(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result_active, []}},
				   {options,  [{active, true} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result_active, []}},
				   {options, [{active, true} | ClientOpts]}]),
        
    ssl_test_lib:check_result(Server, ok, Client, ok),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


%%--------------------------------------------------------------------
ipv6() ->
    [{require, ipv6_hosts},
     {doc,"Test ipv6."}].
ipv6(Config) when is_list(Config) ->
    {ok, Hostname0} = inet:gethostname(),
    
    case lists:member(list_to_atom(Hostname0), ct:get_config(ipv6_hosts)) of
	true ->
	    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
	    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
	    {ClientNode, ServerNode, Hostname} = 
		ssl_test_lib:run_where(Config, ipv6),
	    Server = ssl_test_lib:start_server([{node, ServerNode}, 
				   {port, 0}, {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  
				    [inet6, {active, false} | ServerOpts]}]),
	    Port = ssl_test_lib:inet_port(Server), 
	    Client = ssl_test_lib:start_client([{node, ClientNode}, 
				   {port, Port}, {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, 
				    [inet6, {active, false} | ClientOpts]}]),
	    
	    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			       [self(), Client, Server]),
	    
	    ssl_test_lib:check_result(Server, ok, Client, ok),
	    
	    ssl_test_lib:close(Server),
	    ssl_test_lib:close(Client);
	false ->
	    {skip, "Host does not support IPv6"}
    end.


    

%%--------------------------------------------------------------------
invalid_options() ->
    [{doc,"Test what happens when we give invalid options"}].
       
invalid_options(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    
    Check = fun(Client, Server, {versions, [sslv2, sslv3]} = Option) ->
		    ssl_test_lib:check_result(Server, 
					      {error, {options, {sslv2, Option}}}, 
					      Client,
					      {error, {options, {sslv2, Option}}});
	       (Client, Server, Option) ->
		    ssl_test_lib:check_result(Server, 
					      {error, {options, Option}}, 
					      Client,
					      {error, {options, Option}})
	    end,

    TestOpts = 
         [{versions, [sslv2, sslv3]}, 
          {verify, 4}, 
          {verify_fun, function},
          {fail_if_no_peer_cert, 0}, 
          {verify_client_once, 1},
          {depth, four}, 
          {certfile, 'cert.pem'}, 
          {keyfile,'key.pem' }, 
          {password, foo},
          {cacertfile, ""}, 
          {dhfile,'dh.pem' },
          {ciphers, [{foo, bar, sha, ignore}]},
          {reuse_session, foo},
          {reuse_sessions, 0},
          {renegotiate_at, "10"},
          {mode, depech},
          {packet, 8.0},
          {packet_size, "2"},
          {header, a},
          {active, trice},
          {key, 'key.pem' }],

    [begin
	 Server =
	     ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					{from, self()},
					{options, [TestOpt | ServerOpts]}]),
	 %% Will never reach a point where port is used.
	 Client =
	     ssl_test_lib:start_client_error([{node, ClientNode}, {port, 0},
					      {host, Hostname}, {from, self()},
					      {options, [TestOpt | ClientOpts]}]),
	 Check(Client, Server, TestOpt),
	 ok
     end || TestOpt <- TestOpts],
    ok.


%%--------------------------------------------------------------------
default_reject_anonymous()->
    [{doc,"Test that by default anonymous cipher suites are rejected "}].
default_reject_anonymous(Config) when is_list(Config) ->
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    Version = ssl_test_lib:protocol_version(Config),
    TLSVersion = ssl_test_lib:tls_version(Version),
    
   [CipherSuite | _] = ssl_test_lib:ecdh_dh_anonymous_suites(TLSVersion),
    
    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
                                              {host, Hostname},
                                              {from, self()},
                                              {options,
                                               [{ciphers,[CipherSuite]} |
                                                ClientOpts]}]),

    ssl_test_lib:check_server_alert(Server, Client, insufficient_security).


%%--------------------------------------------------------------------
der_input() ->
    [{doc,"Test to input certs and key as der"}].

der_input(Config) when is_list(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    DHParamFile = filename:join(DataDir, "dHParam.pem"),

    {status, _, _, StatusInfo} = sys:get_status(whereis(ssl_manager)),
    [_, _,_, _, Prop] = StatusInfo,
    State = ssl_test_lib:state(Prop),
    [CADb | _] = element(6, State),

    Size = ets:info(CADb, size),

    SeverVerifyOpts = ssl_test_lib:ssl_options(server_rsa_opts, Config),
    {ServerCert, ServerKey, ServerCaCerts, DHParams} = der_input_opts([{dhfile, DHParamFile} |
								       SeverVerifyOpts]),
    ClientVerifyOpts = ssl_test_lib:ssl_options(client_rsa_opts, Config),
    {ClientCert, ClientKey, ClientCaCerts, DHParams} = der_input_opts([{dhfile, DHParamFile} |
								       ClientVerifyOpts]),
    ServerOpts = [{verify, verify_peer}, {fail_if_no_peer_cert, true},
		  {dh, DHParams},
		  {cert, ServerCert}, {key, ServerKey}, {cacerts, ServerCaCerts}],
    ClientOpts = [{verify, verify_peer}, {fail_if_no_peer_cert, true},
		  {dh, DHParams},
		  {cert, ClientCert}, {key, ClientKey}, {cacerts, ClientCaCerts}],
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result, []}},
					{options, [{active, false} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result, []}},
					{options, [{active, false} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    Size = ets:info(CADb, size).

%%--------------------------------------------------------------------
der_input_opts(Opts) ->
    Certfile = proplists:get_value(certfile, Opts),
    CaCertsfile = proplists:get_value(cacertfile, Opts),
    Keyfile = proplists:get_value(keyfile, Opts),
    Dhfile = proplists:get_value(dhfile, Opts),
    [{_, Cert, _}] = ssl_test_lib:pem_to_der(Certfile),
    [{Asn1Type, Key, _}]  = ssl_test_lib:pem_to_der(Keyfile),
    [{_, DHParams, _}]  = ssl_test_lib:pem_to_der(Dhfile),
    CaCerts =
	lists:map(fun(Entry) ->
			  {_, CaCert, _} = Entry,
			  CaCert
		  end, ssl_test_lib:pem_to_der(CaCertsfile)),
    {Cert, {Asn1Type, Key}, CaCerts, DHParams}.


%%--------------------------------------------------------------------
defaults(Config) when is_list(Config)->
    Versions = ssl:versions(),
    true = lists:member(sslv3, proplists:get_value(available, Versions)),
    false = lists:member(sslv3,  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1', proplists:get_value(available, Versions)),
    false = lists:member('tlsv1',  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1.1', proplists:get_value(available, Versions)),
    false = lists:member('tlsv1.1',  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1.2', proplists:get_value(available, Versions)),
    true = lists:member('tlsv1.2',  proplists:get_value(supported, Versions)),    
    false = lists:member({rsa,rc4_128,sha}, ssl:cipher_suites()),
    true = lists:member({rsa,rc4_128,sha}, ssl:cipher_suites(all)),
    false = lists:member({rsa,des_cbc,sha}, ssl:cipher_suites()),
    true = lists:member({rsa,des_cbc,sha}, ssl:cipher_suites(all)),
    false = lists:member({dhe_rsa,des_cbc,sha}, ssl:cipher_suites()),
    true = lists:member({dhe_rsa,des_cbc,sha}, ssl:cipher_suites(all)),
    true = lists:member('dtlsv1.2', proplists:get_value(available_dtls, Versions)),
    true = lists:member('dtlsv1', proplists:get_value(available_dtls, Versions)),
    true = lists:member('dtlsv1.2', proplists:get_value(supported_dtls, Versions)),
    false = lists:member('dtlsv1', proplists:get_value(supported_dtls, Versions)).

%%--------------------------------------------------------------------
reuseaddr() ->
    [{doc,"Test reuseaddr option"}].

reuseaddr(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options,  [{active, false} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options, [{active, false} | ClientOpts]}]),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    
    Server1 =
	ssl_test_lib:start_server([{node, ServerNode}, {port, Port},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false} | ServerOpts]}]),
    Client1 =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{active, false} | ClientOpts]}]),

    ssl_test_lib:check_result(Server1, ok, Client1, ok),
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------
tls_tcp_reuseaddr() ->
    [{doc, "Reference test case."}].
tls_tcp_reuseaddr(Config) when is_list(Config) ->
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {transport, gen_tcp},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options,  [{active, false}, {reuseaddr, true}]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
                                   {transport, gen_tcp},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options, [{active, false}]}]),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    
    Server1 =
	ssl_test_lib:start_server([{node, ServerNode}, {port, Port},
				   {from, self()},
				   {transport, gen_tcp},
				   {mfa, {?MODULE, tcp_send_recv_result, []}},
				   {options,  [{active, false}, {reuseaddr, true}]}]),
    Client1 =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
                                   {transport, gen_tcp}, 
				   {mfa, {?MODULE, tcp_send_recv_result, []}},
				   {options, [{active, false}]}]),

    ssl_test_lib:check_result(Server1, ok, Client1, ok),
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client1).


%%--------------------------------------------------------------------
tls_ciphersuite_vs_version()  ->
    [{doc,"Test a SSLv3 client cannot negotiate a TLSv* cipher suite."}].
tls_ciphersuite_vs_version(Config) when is_list(Config) ->
    
    {_ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    
    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    
    {ok, Socket} = gen_tcp:connect(Hostname, Port, [binary, {active, false}]),
    ok = gen_tcp:send(Socket, 
		      <<22, 3,0, 49:16, % handshake, SSL 3.0, length
			1, 45:24, % client_hello, length
			3,0, % SSL 3.0
			16#deadbeef:256, % 32 'random' bytes = 256 bits
			0, % no session ID
			%% three cipher suites -- null, one with sha256 hash and one with sha hash
			6:16, 0,255, 0,61, 0,57, 
			1, 0 % no compression
		      >>),
    {ok, <<22, RecMajor:8, RecMinor:8, _RecLen:16, 2, HelloLen:24>>} = gen_tcp:recv(Socket, 9, 10000),
    {ok, <<HelloBin:HelloLen/binary>>} = gen_tcp:recv(Socket, HelloLen, 5000),
    ServerHello = tls_handshake:decode_handshake({RecMajor, RecMinor}, 2, HelloBin),
    case ServerHello of
	#server_hello{server_version = {3,0}, cipher_suite = <<0,57>>} -> 
	    ok;
	_ ->
	    ct:fail({unexpected_server_hello, ServerHello})
    end.
			
%%--------------------------------------------------------------------
conf_signature_algs() ->
    [{doc,"Test to set the signature_algs option on both client and server"}].
conf_signature_algs(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false}, {signature_algs, [{sha, rsa}]} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{active, false}, {signature_algs, [{sha, rsa}]} | ClientOpts]}]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			 [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


%%--------------------------------------------------------------------
no_common_signature_algs()  ->
    [{doc,"Set the signature_algs option so that there client and server does not share any hash sign algorithms"}].
no_common_signature_algs(Config) when is_list(Config) ->
    
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),


    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, [{signature_algs, [{sha256, rsa}]}
							 | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
                                              {host, Hostname},
                                              {from, self()},
                                              {options, [{signature_algs, [{sha384, rsa}]}
                                                         | ClientOpts]}]),
    
    ssl_test_lib:check_server_alert(Server, Client, insufficient_security).


%%--------------------------------------------------------------------
connect_twice() ->
    [{doc,""}].
connect_twice(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{keepalive, true},{active, false}
					       | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{keepalive, true},{active, false}
					      | ClientOpts]}]),
    Server ! listen,

    {Client1, #sslsocket{}} =
	ssl_test_lib:start_client([return_socket,
				   {node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{keepalive, true},{active, false}
					      | ClientOpts]}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			 [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:check_result(Server, ok, Client1, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------

rizzo() ->
    [{doc, "Test that there is a 1/n-1-split for non RC4 in 'TLS < 1.1' as it is
    vunrable to Rizzo/Dungon attack"}].

rizzo(Config) when is_list(Config) ->
    Prop = proplists:get_value(tc_group_properties, Config),
    Version = proplists:get_value(name, Prop),
    NVersion = ssl_test_lib:protocol_version(Config, tuple),
    Ciphers  = ssl:filter_cipher_suites(ssl:cipher_suites(all, NVersion),  
                                        [{key_exchange, 
                                          fun(Alg) when Alg == ecdh_rsa; Alg == ecdhe_rsa-> 
                                                  true;
                                             (_) -> 
                                                  false 
                                          end},
                                         {cipher, 
                                          fun(rc4_128) -> 
                                                  false;
                                             (chacha20_poly1305) ->
                                                  false;
                                             (_) -> 
                                                  true 
                                          end}]),

    run_send_recv_rizzo(Ciphers, Config, Version,
			 {?MODULE, send_recv_result_active_rizzo, []}).
%%--------------------------------------------------------------------
no_rizzo_rc4() ->
    [{doc,"Test that there is no 1/n-1-split for RC4 as it is not vunrable to Rizzo/Dungon attack"}].

no_rizzo_rc4(Config) when is_list(Config) ->
    Prop = proplists:get_value(tc_group_properties, Config),
    Version = proplists:get_value(name, Prop),
    NVersion = ssl_test_lib:protocol_version(Config, tuple),
    %% Test uses RSA certs
    Ciphers  = ssl:filter_cipher_suites(ssl_test_lib:rc4_suites(NVersion),  
                                        [{key_exchange, 
                                          fun(Alg) when Alg == ecdh_rsa; Alg == ecdhe_rsa-> 
                                                  true;
                                             (_) -> 
                                                  false 
                                          end}]),
    run_send_recv_rizzo(Ciphers, Config, Version,
			{?MODULE, send_recv_result_active_no_rizzo, []}).

rizzo_one_n_minus_one() ->
    [{doc,"Test that the 1/n-1-split mitigation of Rizzo/Dungon attack can be explicitly selected"}].

rizzo_one_n_minus_one(Config) when is_list(Config) ->
    Prop = proplists:get_value(tc_group_properties, Config),
    Version = proplists:get_value(name, Prop),
    NVersion = ssl_test_lib:protocol_version(Config, tuple),
    Ciphers  = ssl:filter_cipher_suites(ssl:cipher_suites(all, NVersion),
                                        [{key_exchange, 
                                          fun(Alg) when Alg == ecdh_rsa; Alg == ecdhe_rsa-> 
                                                  true;
                                             (_) -> 
                                                  false 
                                          end}, 
                                         {cipher, 
                                          fun(rc4_128) ->
                                                  false;
                                             %% TODO: remove this clause when chacha is fixed!
                                             (chacha20_poly1305) ->
                                                  false;
                                             (_) -> 
                                                  true 
                                          end}]),
    run_send_recv_rizzo(Ciphers, Config, Version,
                        {?MODULE, send_recv_result_active_rizzo, []}).

rizzo_zero_n() ->
    [{doc,"Test that the 0/n-split mitigation of Rizzo/Dungon attack can be explicitly selected"}].

rizzo_zero_n(Config) when is_list(Config) ->
    Prop = proplists:get_value(tc_group_properties, Config),
    Version = proplists:get_value(name, Prop),
    NVersion = ssl_test_lib:protocol_version(Config, tuple),
    Ciphers  = ssl:filter_cipher_suites(ssl:cipher_suites(default, NVersion),
                                        [{cipher, 
                                          fun(rc4_128) ->
                                                  false;
                                             (_) -> 
                                                  true 
                                          end}]),
    run_send_recv_rizzo(Ciphers, Config, Version,
			 {?MODULE, send_recv_result_active_no_rizzo, []}).

rizzo_disabled() ->
    [{doc,"Test that the mitigation of Rizzo/Dungon attack can be explicitly disabled"}].

rizzo_disabled(Config) when is_list(Config) ->
    Prop = proplists:get_value(tc_group_properties, Config),
    Version = proplists:get_value(name, Prop),
    NVersion = ssl_test_lib:protocol_version(Config, tuple),
    Ciphers  = ssl:filter_cipher_suites(ssl:cipher_suites(default, NVersion),
                                        [{cipher, 
                                          fun(rc4_128) ->
                                                  false;
                                             (_) -> 
                                                  true 
                                          end}]),
    run_send_recv_rizzo(Ciphers, Config, Version,
			 {?MODULE, send_recv_result_active_no_rizzo, []}).

%%--------------------------------------------------------------------
new_server_wants_peer_cert() ->
    [{doc, "Test that server configured to do client certification does"
      " not reuse session without a client certificate."}].
new_server_wants_peer_cert(Config) when is_list(Config) ->
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    VServerOpts = [{verify, verify_peer}, {fail_if_no_peer_cert, true}
		  | ssl_test_lib:ssl_options(server_verification_opts, Config)],
    ClientOpts = ssl_test_lib:ssl_options(client_verification_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {mfa, {?MODULE, peercert_result, []}},
				   {options,  [ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options, ClientOpts}]),

    Monitor = erlang:monitor(process, Server),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    receive
	{'DOWN', Monitor, _, _, _} ->
	    ok
    end,
    
    Server1 = ssl_test_lib:start_server([{node, ServerNode}, {port, Port},
					 {from, self()},
					 {mfa, {?MODULE, peercert_result, []}},
					 {options,  VServerOpts}]), 
    Client1 =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, no_result, []}},
				   {options, [ClientOpts]}]),

    CertFile = proplists:get_value(certfile, ClientOpts),
    [{'Certificate', BinCert, _}]= ssl_test_lib:pem_to_der(CertFile),

    ServerMsg = {error, no_peercert},
    Sever1Msg = {ok, BinCert},
   
    ssl_test_lib:check_result(Server, ServerMsg, Server1, Sever1Msg),

    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Client),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------

tls_versions_option() ->
    [{doc,"Test API versions option to connect/listen."}].
tls_versions_option(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    Supported = proplists:get_value(supported, ssl:versions()),
    Available = proplists:get_value(available, ssl:versions()),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, [{versions, Supported} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    Server ! listen,				       
    
    ErrClient = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port}, 
						 {host, Hostname},
						 {from, self()},
						 {options, [{versions , Available -- Supported} | ClientOpts]}]),
    receive
	{Server, _} ->
	    ok
    end,	    
    ssl_test_lib:check_client_alert(ErrClient, protocol_version).


%%--------------------------------------------------------------------
unordered_protocol_versions_server() ->
    [{doc,"Test that the highest protocol is selected even" 
      " when it is not first in the versions list."}].

unordered_protocol_versions_server(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, [{versions, ['tlsv1.1', 'tlsv1.2']} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, ClientOpts}]),

    ServerMsg = ClientMsg = {ok,'tlsv1.2'},    
    ssl_test_lib:check_result(Server, ServerMsg, Client, ClientMsg).

%%--------------------------------------------------------------------
unordered_protocol_versions_client() ->
    [{doc,"Test that the highest protocol is selected even" 
      " when it is not first in the versions list."}].

unordered_protocol_versions_client(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, ServerOpts }]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options,  [{versions, ['tlsv1.1', 'tlsv1.2']} | ClientOpts]}]),

    ServerMsg = ClientMsg = {ok, 'tlsv1.2'},    
    ssl_test_lib:check_result(Server, ServerMsg, Client, ClientMsg).
  
%%--------------------------------------------------------------------
max_handshake_size() ->
    [{doc,"Test that we can set max_handshake_size to max value."}].

max_handshake_size(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options,  [{max_handshake_size, 8388607} |ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, [{max_handshake_size, 8388607} | ClientOpts]}]),
 
    ssl_test_lib:check_result(Server, ok, Client, ok).
  

%%--------------------------------------------------------------------

accept_pool() ->
    [{doc,"Test having an accept pool."}].
accept_pool(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server0 = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{accepters, 3},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server0),
    [Server1, Server2] = ssl_test_lib:accepters(2),

    Client0 = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					 {host, Hostname},
					 {from, self()}, 
					 {mfa, {ssl_test_lib, send_recv_result_active, []}},
					 {options, ClientOpts}
					]),
    
    Client1 = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					 {host, Hostname},
					 {from, self()}, 
					 {mfa, {ssl_test_lib, send_recv_result_active, []}},
					 {options, ClientOpts}
					]),
    
    Client2 = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					 {host, Hostname},
					 {from, self()}, 
					 {mfa, {ssl_test_lib, send_recv_result_active, []}},
					 {options, ClientOpts}
					]),

    ssl_test_lib:check_ok([Server0, Server1, Server2, Client0, Client1, Client2]),
    
    ssl_test_lib:close(Server0),
    ssl_test_lib:close(Server1),
    ssl_test_lib:close(Server2),
    ssl_test_lib:close(Client0),
    ssl_test_lib:close(Client1),
    ssl_test_lib:close(Client2).
    

%%--------------------------------------------------------------------
%% Internal functions ------------------------------------------------
%%--------------------------------------------------------------------
send_recv_result(Socket) ->
    ssl:send(Socket, "Hello world"),
    {ok,"Hello world"} = ssl:recv(Socket, 11),
    ok.
tcp_send_recv_result(Socket) ->
    gen_tcp:send(Socket, "Hello world"),
    {ok,"Hello world"} = gen_tcp:recv(Socket, 11),
    ok.

basic_verify_test_no_close(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ClientOpts}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    {Server, Client}.

basic_test(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ClientOpts}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).





send_recv_result_active_rizzo(Socket) ->
    ssl:send(Socket, "Hello world"),
    "Hello world" = ssl_test_lib:active_recv(Socket, 11),
    ok.

send_recv_result_active_no_rizzo(Socket) ->
    ssl:send(Socket, "Hello world"),
    "Hello world" = ssl_test_lib:active_recv(Socket, 11),
    ok.

result_ok(_Socket) ->
    ok.

rizzo_add_mitigation_option(Value, Config) ->
    lists:foldl(fun(Opt, Acc) ->
                    case proplists:get_value(Opt, Acc) of
                      undefined -> Acc;
                      C ->
                        N = lists:keystore(beast_mitigation, 1, C,
                                           {beast_mitigation, Value}),
                        lists:keystore(Opt, 1, Acc, {Opt, N})
                    end
                end, Config,
                [client_opts, client_dsa_opts, server_opts, server_dsa_opts,
                 server_ecdsa_opts, server_ecdh_rsa_opts]).
    

erlang_ssl_receive(Socket, Data) ->
    case ssl_test_lib:active_recv(Socket, length(Data)) of
        Data ->
            ok;
        Other ->
            ct:fail({{expected, Data}, {got, Other}})
    end.



run_send_recv_rizzo(Ciphers, Config, Version, Mfa) ->
    Result =  lists:map(fun(Cipher) ->
				rizzo_test(Cipher, Config, Version, Mfa) end,
			Ciphers),
    case lists:flatten(Result) of
	[] ->
	    ok;
	Error ->
	    ct:log("Cipher suite errors: ~p~n", [Error]),
	    ct:fail(cipher_suite_failed_see_test_case_log)
    end.



rizzo_test(Cipher, Config, Version, Mfa) ->
   {ClientOpts, ServerOpts} = client_server_opts(Cipher, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, Mfa},
			   {options, [{active, true}, {ciphers, [Cipher]},
				       {versions, [Version]}
				      | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, Mfa},
			   {options, [{active, true}, {ciphers, [Cipher]}| ClientOpts]}]),

    Result = ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    case Result of
	ok ->
	    [];
	Error ->
	    [{Cipher, Error}]
    end.

client_server_opts(#{key_exchange := KeyAlgo}, Config)
  when KeyAlgo == rsa orelse
       KeyAlgo == dhe_rsa orelse
       KeyAlgo == ecdhe_rsa orelse
       KeyAlgo == rsa_psk orelse
       KeyAlgo == srp_rsa ->
    {ssl_test_lib:ssl_options(client_opts, Config),
     ssl_test_lib:ssl_options(server_opts, Config)};
client_server_opts(#{key_exchange := KeyAlgo}, Config) when KeyAlgo == dss orelse KeyAlgo == dhe_dss ->
    {ssl_test_lib:ssl_options(client_dsa_opts, Config),
     ssl_test_lib:ssl_options(server_dsa_opts, Config)};
client_server_opts(#{key_exchange := KeyAlgo}, Config) when KeyAlgo == ecdh_ecdsa orelse KeyAlgo == ecdhe_ecdsa ->
    {ssl_test_lib:ssl_options(client_opts, Config),
     ssl_test_lib:ssl_options(server_ecdsa_opts, Config)};
client_server_opts(#{key_exchange := KeyAlgo}, Config) when KeyAlgo == ecdh_rsa ->
    {ssl_test_lib:ssl_options(client_opts, Config),
     ssl_test_lib:ssl_options(server_ecdh_rsa_opts, Config)}.

protocol_info_result(Socket) ->
    {ok, [{protocol, PVersion}]} = ssl:connection_information(Socket, [protocol]),
    {ok, PVersion}.

version_info_result(Socket) ->
    {ok, [{version, Version}]} = ssl:connection_information(Socket, [version]),
    {ok, Version}.

  
connect_dist_s(S) ->
    Msg = term_to_binary({erlang,term}),
    ok = ssl:send(S, Msg).

connect_dist_c(S) ->
    Test = binary_to_list(term_to_binary({erlang,term})),
    {ok, Test} = ssl:recv(S, 0, 10000),
    ok.




get_invalid_inet_option(Socket) ->
    {error, {options, {socket_options, foo, _}}} = ssl:getopts(Socket, [foo]),
    ok.


dummy(_Socket) ->
    %% Should not happen as the ssl connection will not be established
    %% due to fatal handshake failiure
    exit(kill).



version_option_test(Config, Version) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false}, {versions, [Version]}| ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{active, false}, {versions, [Version]}| ClientOpts]}]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
	   [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).


    
wait_for_send(Socket) ->
    %% Make sure TLS process processed send message event
    _ = ssl:connection_information(Socket).


connection_info_result(Socket) ->
    {ok, Info} = ssl:connection_information(Socket, [protocol, selected_cipher_suite]),
    {ok, {proplists:get_value(protocol, Info), proplists:get_value(selected_cipher_suite, Info)}}.
