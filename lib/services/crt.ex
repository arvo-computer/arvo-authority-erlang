defmodule CA.CRT do
  @moduledoc "X.509 Certificates."

  def subj({:rdnSequence, attrs}) do
      {:rdnSequence, :lists.map(fn
          [{t,oid,{:uTF8String,x}}]   -> [{t,oid,:asn1rt_nif.encode_ber_tlv({12, :erlang.iolist_to_binary(x)})}]
          [{t,oid,x}] when is_list(x) -> [{t,oid,:asn1rt_nif.encode_ber_tlv({19, :erlang.iolist_to_binary(x)})}]
          [{t,oid,x}] -> [{t,oid,x}] end, attrs)}
  end

  def unsubj({:rdnSequence, attrs}) do
      {:rdnSequence, :lists.map(fn [{t,oid,x}] when is_binary(x) ->
           case :asn1rt_nif.decode_ber_tlv(x) do
                {{12,a},_} -> [{t,oid,{:uTF8String,a}}]
                {{19,a},_} -> [{t,oid,:erlang.binary_to_list(a)}]
           end
           {t,oid,x} -> [{t,oid,x}]
           x -> x
      end, attrs)}
  end

  def extract(code, person) do
      case :lists.keyfind(code, 2, person) do
           false -> []
           {_, _, <<19,_,bin::binary>>} -> bin
           {_, _, {:printable, str}} -> str
           {_, _, {:utf8, str}} -> str
      end
  end

  def pair([],acc), do: acc
  def pair([x],acc), do: [x|acc]
  def pair([a,b|t],acc), do: pair(t,[{hd(mapOids([:oid.decode(a)])),b}|acc])

  def mapOidsDecode(list) do
      :lists.map(fn x ->
         :erlang.iolist_to_binary(:string.join(:lists.map(fn y -> :erlang.integer_to_list(y) end,
         :erlang.tuple_to_list(:oid.decode(x))),'.')) end, list)
  end

  def mapOid(x)     do :erlang.iolist_to_binary(:string.join(:lists.map(fn y -> :erlang.integer_to_list(y) end, :erlang.tuple_to_list(x)),'.')) end
  def mapOids(list) do :lists.map(fn x -> mapOid(x) end, list) end
  def isString(bin) do :lists.foldl(fn x, acc when x < 20 -> acc + 1 ; _, acc -> acc end, 0, :erlang.binary_to_list(bin)) <= 0 end

  def oid({1,3,6,1,5,5,7,1,1}, v),        do: {:authorityInfoAccess, pair(v,[])}
  def oid({1,3,6,1,4,1,11129,2,4,2}, v),  do: {:signedCertificateTimestamp, :base64.encode(hd(pair(v,[])))}
  def oid({1,3,6,1,5,5,7,1,11},v),        do: {:subjectInfoAccess, pair(v,[])}
  def oid({1,3,6,1,5,5,7,1,3}, v),        do: {:qcStatements, :lists.map(fn x -> case isString(x) do false -> mapOid(:oid.decode(x)) ; true -> x end end, v) }
  def oid({2,5,29,9},v),                  do: {:subjectDirectoryAttributes, pair(v,[])}
  def oid({2,5,29,14},v),                 do: {:subjectKeyIdentifier, :base64.encode(hd(pair(v,[])))}
  def oid({2,5,29,15},[v]),               do: {:keyUsage, CA.EST.decodeKeyUsage(<<3,2,v::binary>>) }
  def oid({2,5,29,16},v),                 do: {:privateKeyUsagePeriod, v}
  def oid({2,5,29,17},v),                 do: {:subjectAltName, :lists.map(fn x -> case isString(x) do false -> mapOid(:oid.decode(x)) ; true -> x end end, v) }
  def oid({2,5,29,37},v),                 do: {:extKeyUsage, mapOids(:lists.map(fn x -> :oid.decode(x) end, v)) }
  def oid({2,5,29,19},v),                 do: {:basicConstraints, v}
  def oid({2,5,29,31},v),                 do: {:cRLDistributionPoints, pair(v,[])}
  def oid({2,5,29,32},v),                 do: {:certificatePolicies, :lists.map(fn x -> case isString(x) do false -> mapOid(:oid.decode(x)) ; true -> x end end, v) }
  def oid({2,5,29,35},v),                 do: {:authorityKeyIdentifier, v}
  def oid({2,5,29,46},v),                 do: {:freshestCRL, pair(v,[])}
  def oid({1,2,840,113549,1,9,3},v),      do: {:contentType, CA.AT.oid(CA.EST.decodeObjectIdentifier(v)) }
  def oid({1,2,840,113549,1,9,4},v),      do: {:messageDigest, :base64.encode(:erlang.element(2,:KEP.decode(:MessageDigest, v)))}
  def oid({1,2,840,113549,1,9,5},v),      do: {:signingTime, :erlang.element(2,:erlang.element(1,:asn1rt_nif.decode_ber_tlv(v)))}
  def oid({1,2,840,113549,1,9,16,2,14},v) do
      {:ok, {:ContentInfo, oid, value}} = :KEP.decode(:ContentInfo,v)
      {:ok, {:SignedData, _, _alg, {_,_,x}, _c, _x1, _si}} = :KEP.decode(:SignedData, value)
      {:ok, {:TSTInfo, _vsn, _oid, {:MessageImprint, _, x}, serial, ts, _,_,_,_}} = :KEP.decode(:TSTInfo, x)
      {:timeStampToken, {hd(mapOids([oid])), serial, :erlang.iolist_to_binary(ts), :base64.encode(x)}}
      end
  def oid({1,2,840,113549,1,9,16,2,18},v) do {:signerAttr, v} end
  def oid({1,2,840,113549,1,9,16,2,19},v) do {:otherSigCert, v} end
  def oid({1,2,840,113549,1,9,16,2,20},v) do
      {:ok, {:ContentInfo, oid, value}} = :KEP.decode(:ContentInfo,v)
      {:ok, {:SignedData, _, _alg, {_,_,x}, _c, _x1, _si}} = :KEP.decode(:SignedData, value)
      {:ok, {:TSTInfo, _vsn, _oid, {:MessageImprint, _, x}, serial, ts, _,_,_,_}} = :KEP.decode(:TSTInfo, x)
      {:contentTimestamp, {hd(mapOids([oid])), serial, :erlang.iolist_to_binary(ts), :base64.encode(x)}}
  end
  def oid({1,2,840,113549,1,9,16,2,22},v) do
      {:ok, x} = :KEP.decode(:CompleteRevocationRefs, v)
      {:revocationRefs, x}
  end
  def oid({1, 2, 840, 113549, 1, 9, 16, 2, 21}, v) do
      {:certificateRefs, v}
  end
  def oid({1, 2, 840, 113549, 1, 9, 16, 2, 23}, v) do
      {:ok, certList} = :KEP.decode(:Certificates, v)
      list = :lists.map(fn cert -> CA.CRT.parseCert(cert) end, certList)
      {:certificateValues, list}
  end
  def oid({1, 2, 840, 113549, 1, 9, 16, 2, 24}, v) do
      {:ok, {:RevocationValues, :asn1_NOVALUE, ocspVals, :asn1_NOVALUE}} = :KEP.decode(:RevocationValues, v)
      {:ok, list} = :KEP.decode(:BasicOCSPResponses, ocspVals)
      list = :lists.map(fn {:BasicOCSPResponse,{:ResponseData,_ver,{_,rdn},_time,_responses,_ext},_alg,_bin,_} -> CA.RDN.rdn(rdn) end, list)
      {:revocationValues, list}
  end

  def oid({1, 2, 840, 113549, 1, 9, 16, 2, 47}, v) do
      {:ok, {:SigningCertificateV2,[{:ESSCertIDv2, _, _, {_,_,serial}}],_}} = :KEP.decode(:SigningCertificateV2, v)
      {:signingCertificateV2, serial}
  end

  def oid(x,v) when is_binary(x), do: {:oid.decode(x),pair(v,[])}
  def oid(x,v), do: {x,v}

  def flat(code,{k,v},acc) when is_integer(k), do: [flat(code,v,acc)|acc]
  def flat(code,{k,_v},acc), do: [flat(code,k,acc)|acc]
  def flat(code,k,acc) when is_list(k), do: [:lists.map(fn x -> flat(code,x,acc) end, k)|acc]
  def flat(_code,k,acc) when is_binary(k), do: [k|acc]

  def baseLength(oid) when is_tuple(oid) do CA.Curve.getLength(CA.KnownCurves.getCurveByOid(oid)) end
  def baseLength(_) do 256 end

  def decodePointFromPublic(agreement,params,publicKey) do
      bin = :binary.part(publicKey,1,:erlang.size(publicKey)-1)
      baseLength = baseLength(params)
      xs = :binary.part(bin, 0, baseLength)
      ys = :binary.part(bin, baseLength, :erlang.size(bin) - baseLength)
      [ x: CA.ECDSA.numberFromString(xs),
        y: CA.ECDSA.numberFromString(ys),
        scheme: CA.AT.oid(agreement),
        curve: CA.AT.oid(params),
      ]
  end

  def decodePublicKey(agreement,{:asn1_OPENTYPE, params},publicKey) do decodePublicKey(agreement,params,publicKey) end
  def decodePublicKey(agreement,params,publicKey) do
      case agreement do
           {1,2,840,113549,1,1,1} -> # RSA
                {:ok, key} = :"PKCS-1".decode(:'RSAPublicKey', publicKey)
                [key: key, scheme: :RSA]
           {1,2,840,10045,2,1} -> # ECDSA
                params = CA.EST.decodeObjectIdentifier(params)
                decodePointFromPublic(agreement,params,publicKey)
           {1,2,804,2,1,1,1,1,3,1,1} -> # ДСТУ-4145, ДСТУ-7564
                {:ok,p} = :DSTU.decode(:DSTU4145Params, params)
                [key: publicKey, scheme: CA.AT.oid(agreement), field: p]
           _ -> :io.format 'new publicKey agreement scheme detected: ~p~n', [agreement]
                :base64.encode publicKey
      end
  end

  def parseCertPEM(file)  do {:ok, bin} = :file.read_file file ; list = :public_key.pem_decode(bin) ; :lists.map(fn x -> parseCert(:public_key.pem_entry_decode(x)) end, list) end
  def parseCertB64(file)  do {:ok, bin} = :file.read_file file ; parseCertBin(:base64.decode(bin)) end
  def parseCertFile(file) do {:ok, bin} = :file.read_file file ; parseCertBin(bin) end
  def parseCertBin(bin)   do {:ok, cert} = :"AuthenticationFramework".decode(:Certificate, bin) ; parseCert(cert) end

  def parseCert(cert, _) do parseCert(cert) end
  def parseCert({:certificate, cert}) do parseCert(cert) end
  def parseCert(cert) do
      {:Certificate, tbs, _, _} = case cert do
         {:Certificate, tbs, x, y} -> {:Certificate, tbs, x, y}
         {:Certificate, tbs, x, y, _} -> {:Certificate, tbs, x, y}
      end

      {_, ver, serial, {_,alg,_}, issuer, {_,{_,nb},{_,na}}, issuee,
         {:SubjectPublicKeyInfo, {_, agreement, params}, publicKey}, _b, _c, exts} = tbs
      extensions = :lists.map(fn {:Extension,code,_x,b} ->
         oid(code, :lists.flatten(flat(code,:asn1rt_nif.decode_ber_tlv(b),[])))
      end, exts)
      [ resourceType: :Certificate,
        version: ver,
        signatureAlgorithm: CA.AT.oid(alg),
        subject: CA.RDN.rdn(unsubj(issuee)),
        issuer:  CA.RDN.rdn(unsubj(issuer)),
        serial: :base64.encode(CA.EST.integer(serial)),
        validity: [from: nb, to: na],
        publicKey: decodePublicKey(agreement, params, publicKey),
        extensions: extensions
      ]
  end

end
