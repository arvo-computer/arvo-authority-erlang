defmodule CA.CMS do
  @moduledoc "CA/CMS library."

  def oid(:"id-cms-data"),              do: {1,2,840,113549,1,7,1}
  def oid(:"id-cms-signedData"),        do: {1,2,840,113549,1,7,2}
  def oid(:"id-cms-envelopedData"),     do: {1,2,840,113549,1,7,3}
  def oid(:"id-cms-digestedData"),      do: {1,2,840,113549,1,7,4}
  def oid(:"id-cms-encryptedData"),     do: {1,2,840,113549,1,7,5}

  def contentInfo(cms) do {:ok, ci} = :"CryptographicMessageSyntax-2010".decode :ContentInfo, cms ; ci end
  def contentInfoFile(file) do {:ok, bin} = :file.read_file file ; contentInfo(bin) end

  def map(:'dhSinglePass-stdDH-sha512kdf-scheme'),   do: {:kdf,  :sha512}
  def map(:'dhSinglePass-stdDH-sha384kdf-scheme'),   do: {:kdf,  :sha384}
  def map(:'dhSinglePass-stdDH-sha256kdf-scheme'),   do: {:kdf,  :sha256}
  def map(:'dhSinglePass-stdDH-hkdf-sha256-scheme'), do: {:hkdf, :sha256}
  def map(:'dhSinglePass-stdDH-hkdf-sha384-scheme'), do: {:hkdf, :sha384}
  def map(:'dhSinglePass-stdDH-hkdf-sha512-scheme'), do: {:hkdf, :sha512}

  def sharedInfo(ukm, len), do: {:'ECC-CMS-SharedInfo',
      {:'KeyWrapAlgorithm',{2,16,840,1,101,3,4,1,45},:asn1_NOVALUE}, ukm, <<len::32>>}

  # CMS Codec KARI: ECC+KDF/ECB+AES/KW+256/CBC

  def kari(kari, privateKeyBin, schemeOID, encOID, data, iv) do
      {:'KeyAgreeRecipientInfo',:v3,{_,{_,_,publicKey}},ukm,{_,kdfOID,_},[{_,_,encryptedKey}]} = kari
      {scheme,_} = CA.ALG.lookup(schemeOID)
      {kdf,_} = CA.ALG.lookup(kdfOID)
      {enc,_} = CA.ALG.lookup(encOID)
      sharedKey = :crypto.compute_key(:ecdh,publicKey,privateKeyBin,scheme)
      {_,payload} = :'CMSECCAlgs-2009-02'.encode(:'ECC-CMS-SharedInfo', sharedInfo(ukm,256))
      derived = case map(kdf) do
          {:kdf,hash} -> CA.KDF.derive({:kdf,hash},  sharedKey, 32, payload)
         {:hkdf,hash} -> CA.HKDF.derive({:kdf,hash}, sharedKey, 32, payload)
      end
      unwrap = CA.AES.keyUnwrap(encryptedKey, derived)
      res = CA.AES.decrypt(enc, data, unwrap, iv)
      {:ok, res}
  end

  # CMS Codec KTRI: RSA+RSAES-OAEP

  def ktri(ktri, privateKeyBin, encOID, data, iv) do
      {:'KeyTransRecipientInfo',_vsn,_,{_,schemeOID,_},key} = ktri
      {:rsaEncryption,_} = CA.ALG.lookup schemeOID
      {enc,_} = CA.ALG.lookup(encOID)
      sessionKey = :public_key.decrypt_private(key, privateKeyBin)
      res = CA.AES.decrypt(enc, data, sessionKey, iv)
      {:ok, res}
  end

  # CMS Codec KEKRI: KEK+AES-KW+CBC

  def kekri(kekri, privateKeyBin, encOID, data, iv) do
      {:'KEKRecipientInfo',_vsn,_,{_,kea,_},encryptedKey} = kekri
      _ = CA.ALG.lookup(kea)
      {enc,_} = CA.ALG.lookup(encOID)
      unwrap = CA.AES.keyUnwrap(encryptedKey,privateKeyBin)
      res = CA.AES.decrypt(enc, data, unwrap, iv)
      {:ok, res}
  end

  # CMS DECRYPT API

  def decrypt(cms, {schemeOID, privateKeyBin}) do
      {:ok,{:ContentInfo,_,{:EnvelopedData,_,_,x,y,_}}} = cms
      {:EncryptedContentInfo,_,{_,encOID,{_,<<_::16,iv::binary>>}},data} = y
              case :proplists.get_value(:kari,  x, []) do
        [] -> case :proplists.get_value(:ktri,  x, []) do
        [] -> case :proplists.get_value(:kekri, x, []) do
        [] -> case :proplists.get_value(:pwri,  x, []) do
        [] -> {:error, "Unknown Other Recepient Info"}
              pwri  -> pwri(pwri,   privateKeyBin, encOID, data, iv) end
              kekri -> kekri(kekri, privateKeyBin, encOID, data, iv) end
              ktri  -> ktri(ktri,   privateKeyBin, encOID, data, iv) end
              kari  -> kari(kari,   privateKeyBin, schemeOID, encOID, data, iv)
      end
  end

  # CMS Codec PWRI: PBKDF2+AES-KW+CBC

  def pwri(pwri, privateKeyBin, encOID, data, iv) do
      {:error, ["PWRI not implemented", pwri, privateKeyBin, encOID, data, iv]}
  end

  # Test

  def pem(name), do: hd(:public_key.pem_decode(:erlang.element(2, :file.read_file(name))))
  def testDecryptECC(), do: [cipher: :binary.part(:erlang.element(2, CA.CMS.decrypt(testECC(), testPrivateKeyECC())),0,48)]
  def testDecryptKEK(), do: [cipher: :binary.part(:erlang.element(2, CA.CMS.decrypt(testKEK(), testPrivateKeyKEK())),0,48)]
  def testDecryptRSA(), do: [cipher: :erlang.element(2, CA.CMS.decrypt(testRSA(), testPrivateKeyRSA()))]
  def testDecryptCMS(), do: [cipher: :binary.part(:erlang.element(2, CA.CMS.testCMS()),0,48)]
  def test(),           do:
      [
        testFolder("czo"),
        testFolder("CAdES"),
        testFolder("certs"),
        testFolder("cms"),
        [
          testDecryptECC(),
          testDecryptKEK(),
          testDecryptCMS(),
          testDecryptRSA(),
        ],
      ]

  def parseKeyFile(file)  do {:ok, bin} = :file.read_file file ; list = :public_key.pem_decode(bin) ; :lists.map(fn x -> :public_key.pem_entry_decode(x) end, list) end

  def testFolder(folder \\ "CAdES") do
      :lists.map(fn x -> case :filename.extension(x) do
         '.p7s' -> [cms: byte_size(:erlang.term_to_binary(CA.CMS.parseContentInfoFile(x))), name: x]
         '.txt' -> [smime: byte_size(:erlang.term_to_binary(CA.CMS.parseContentInfoSMIME(x))), name: x]
         '.key' -> [key: byte_size(:erlang.term_to_binary(CA.CMS.parseKeyFile(x))), name: x]
         '.b64' -> [base64: byte_size(:erlang.term_to_binary(CA.CRT.parseCertB64(x))), name: x]
         '.pem' -> [pem: byte_size(:erlang.term_to_binary(CA.CRT.parseCertPEM(x))), name: x]
         '.cer' -> [cert: byte_size(:erlang.term_to_binary(CA.CRT.parseCertFile(x))), name: x]
      end end, :filelib.wildcard ['test/#{folder}/*'])
  end

  def testPrivateKeyECC() do
      privateKey = :public_key.pem_entry_decode(pem("test/certs/client.key"))
      {:'ECPrivateKey',_,privateKeyBin,{:namedCurve,schemeOID},_,_} = privateKey
      {schemeOID,privateKeyBin}
  end

  def testPrivateKeyKEK() do
      {:kek, :binary.decode_hex("0123456789ABCDEF0123456789ABCDEF")}
  end

  def testPrivateKeyRSA() do
      {:ok,bin} = :file.read_file("test/cms/rsa-cms.key")
      pki = :public_key.pem_decode(bin)
      [{:PrivateKeyInfo,_,_}] = pki
      rsa = :public_key.pem_entry_decode(hd(pki))
      {:'RSAPrivateKey',:'two-prime',_n,_e,_d,_,_,_,_,_,_} = rsa
      {:rsaEncryption,rsa}
  end


  def testKEK() do
      {:ok,base} = :file.read_file "test/cms/encrypted2.txt"
      [_,s] = :string.split base, "\n\n"
      x = :base64.decode s
      :'CryptographicMessageSyntax-2010'.decode(:ContentInfo, x)
  end

  def testRSA() do
      {:ok,x} = :file.read_file "test/cms/rsa-cms.p7s"
      :'CryptographicMessageSyntax-2010'.decode(:ContentInfo, x)
  end

  def testCMS() do
      privateKey = :erlang.element(3,:public_key.pem_entry_decode(pem("test/certs/client.key")))
      scheme = :secp384r1
      {:ok,{:ContentInfo,_,{:EnvelopedData,_,_,x,{_,_,{_,_,{_,<<_::16,iv::binary>>}},data},_}}} = testECC()
      [{:kari,{_,:v3,{_,{_,_,publicKey}},ukm,_,[{_,_,encryptedKey}]}}|_] = x
      sharedKey = :crypto.compute_key(:ecdh,publicKey,privateKey,scheme)
      {_,content}  =  :'CMSECCAlgs-2009-02'.encode(:'ECC-CMS-SharedInfo', CA.CMS.sharedInfo(ukm,256))
      kdf = CA.KDF.derive({:kdf, :sha256}, sharedKey, 32, content)
      unwrap = :aes_kw.unwrap(encryptedKey, kdf)
      {:ok, CA.AES.decrypt(:'id-aes256-CBC', data, unwrap, iv)}
  end

  # ASN.1 DER Parsing Facilities

  def parseSignDataFile(file) do
      {_, bin} = :file.read_file file
      parseData(bin)
  end

  def parseRecipientInfo([]) do [] end
  def parseRecipientInfo({scheme,ri}) do {scheme,ri} end
  def parseRecipientInfo(ri) do
      {:RecipientInfo, _, {_,issuer,_}, {_,keyAlg,_}, _data} = ri
      [
         resourceType: :RecipientInfo,
         issuer: CA.RDN.rdn(issuer),
         keyAlg: CA.AT.oid(keyAlg),
      ]
  end

  def parseSignerInfo(si) do
      {:SignerInfo, :v1, {_,{_,issuer,_}}, {_,keyAlg,_}, signedAttrs, {_,signatureAlg,_}, _sign, attrs} = si
      signedAttributes = :lists.map(fn {_,code,[{:asn1_OPENTYPE,b}]}   ->   CA.CE.oid(code, b)
                                       {_,code,[{:asn1_OPENTYPE,b}],_} ->   CA.CE.oid(code, b)
                                       {_,code,b}                      -> { CA.AT.oid(code), b }
                                         end, signedAttrs)
      attributes = case attrs do
          :asn1_NOVALUE -> []
          _ -> :lists.map(fn {_,code,[{:asn1_OPENTYPE,b}]}   ->   CA.CE.oid(code, b)
                             {_,code,[{:asn1_OPENTYPE,b}],_} ->   CA.CE.oid(code, b)
                             {_,code,b}                      -> { CA.AT.oid(code), b }
                            end, attrs)
      end
      [
         resourceType: :SignerInfo,
         issuer: CA.RDN.rdn(issuer),
         keyAlg: CA.AT.oid(keyAlg),
         signatureAlg: CA.AT.oid(signatureAlg),
         signedAttrs: signedAttributes,
         attrs: attributes,
      ]
  end

  def parseDataBin(content) do
      {:ok, envelopedData} = :KEP.decode(:SignedData, content)
      parseData(envelopedData)
  end
  def parseData({:SignedData, ver, _alg, x, c, _x1, sis}) do
      {:EncapsulatedContentInfo, _contentOid, data} = x
      [
         resourceType: :SignedData,
         version: ver,
         cert: parseSignDataCert(case c do {:certificate,cert} -> cert ; c -> c end,sis),
         signerInfo: parseSignerInfos(sis),
         signedContent: data,
      ]
  end

  def parseEnvelopedDataBin(content) do
      {:ok, envelopedData} = :KEP.decode(:EnvelopedData, content)
      parseEnvelopedData(envelopedData)
  end

  def parseEnvelopedData({:EnvelopedData, oid, _, list, ci, _tag}) do
      parseEnvelopedData({:EnvelopedData, oid, list, ci}) end

  def parseEnvelopedData({:EnvelopedData, oid, {:riSet, ri}, ci}) do
      parseEnvelopedData({:EnvelopedData, oid, ri, ci}) end

  def parseEnvelopedData({:EnvelopedData, oid, ri, ci}) do
      {:EncryptedContentInfo, _oid2, {_,encOID,<<_::16,iv::binary>>},data} = case ci do
          {:EncryptedContentInfo, x, {y,encOID,{_,bin}},data} -> {:EncryptedContentInfo, x, {y,encOID,bin},data}
          {:EncryptedContentInfo, x, {y,encOID,bin},data} -> {:EncryptedContentInfo, x, {y,encOID,bin},data}
      end
      [
         resourceType: :EnvelopedData,
         ver: CA.ALG.oid(oid),
         signerInfo: parseRecipientInfos(ri),
         encryption: CA.AT.oid(encOID),
         encryptedContentInfo: [iv: :base64.encode(iv), data: :base64.encode(data)]
      ]
  end

  def parseSignerInfos(sis)      do :lists.map(fn si -> CA.CMS.parseSignerInfo(si) end, sis) end
  def parseRecipientInfos(sis)   do :lists.map(fn si -> CA.CMS.parseRecipientInfo(si) end, sis) end

  def testECC() do
      {:ok,base} = :file.read_file "test/cms/encrypted.txt"
      [_,s] = :string.split base, "\n\n"
      x = :base64.decode s
      :'CryptographicMessageSyntax-2010'.decode(:ContentInfo, x)
  end

  def parseContentInfoSMIME(file) do
      {:ok, smime} = :file.read_file(file)
      [_,base] = :string.split(smime, "\n\n")
      parseContentInfoBin(:base64.decode(base))
  end
  def parseContentInfoB64(file)    do {:ok, bin} = :file.read_file file ; parseContentInfoBin(:base64.decode(bin)) end
  def parseContentInfoFile(file)   do {:ok, bin} = :file.read_file file ; parseContentInfoBin(bin) end
  def parseContentInfoBinUA(bin)   do {:ok, contentInfo} = :KEP.decode(:ContentInfo, bin) ; parseContentInfo(contentInfo, true)  end
  def parseContentInfoBinX509(bin) do {:ok, contentInfo} = :'CryptographicMessageSyntax-2010'.decode(:ContentInfo, bin) ; parseContentInfo(contentInfo, false) end

  def parseContentInfoBin(bin) do
      case :application.get_env(:ca, :ukrainian, :parseContentInfoBinUA) do
           :parseContentInfoBinX509 -> CA.CMS.parseContentInfoBinX509(bin)
             :parseContentInfoBinUA -> CA.CMS.parseContentInfoBinUA(bin)
                                  _ -> CA.CMS.parseContentInfoBinUA(bin)
      end
  end

  def parseContentInfo({:ContentInfo, oid, content}, false) do
      case CA.AT.code(oid) do
           :data          -> parseData(content)
           :signedData    -> parseData(content)
           :envelopedData -> parseEnvelopedData(content)
           _              -> []
      end
  end
  def parseContentInfo({:ContentInfo, oid, content}, true) do
      case CA.AT.code(oid) do
           :data          -> parseDataBin(content)
           :signedData    -> parseDataBin(content)
           :envelopedData -> parseEnvelopedDataBin(content)
           _              -> []
      end
  end

  def parseSignDataCert(:asn1_NOVALUE,_), do: []
  def parseSignDataCert(certs,si),        do: :lists.map(fn cert -> CA.CRT.parseCert(cert, si) end, certs)

end