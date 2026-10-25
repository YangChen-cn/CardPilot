import Foundation

/// Decoded-pixel fingerprints of official card faces shipped by earlier CardPilot catalog versions.
/// Byte hashes cannot be used here because iOS re-encodes bundled PNGs as CgBI; decoded pixels stay stable.
/// Used only to clear a stale copy of an official card face. Personal images never match these fingerprints.
enum LegacyArtworkFingerprints {
    static let byCatalogID: [String: Set<String>] = [
        "bea.hku.student.visa": [
            "074ea179e1d6ca264a4bde2765ace42caa3c4a344379315723b37927bff17f57",
            "7b208191a6c8395947cd5f9f1d6d00c5a828c187fc2cb9f56670920c31e18da0",
        ],
        "bea.udc.diamond": [
            "b72473af2ae5930a7cdc68e7abaf695c7dec6bf60bad60d4c766064b2ef356bf",
        ],
        "bea.udc.diamond.student": [
            "1bcabea54f6b2046a3a7a1e83adb5e9c916b3f085315f444d6b16c77bce99b45",
            "b72473af2ae5930a7cdc68e7abaf695c7dec6bf60bad60d4c766064b2ef356bf",
        ],
        "bochk.chill.platinum": [
            "1987116beb9dd1786804ce738f9badf66e12c14e4f89914e5c13a30ce743363e",
            "5c92834b26486a662168cef270e1bd59210a7fb528729d961d3b3b3e3ba70004",
        ],
        "bochk.gba.youth": [
            "194ac6ba23555b92608df6c4d19ec659bf8e7e3adadcd30230c4fede32307833",
            "1e1285bd8ced3ccf424be905a458719a426ca82e66cd37c8077f5f55f3b7899a",
            "cf2ab6d24998d9f07095ddefe99ca524844f7250f6ee877734afd58fc3b096cc",
        ],
        "bochk.go.diamond": [
            "1848ff24ee0daa6205d61ef9af4069e5bae216c0a9d4b64a39367f9e6c8e6563",
            "3086c1c742f28ae9dc9922f668e3e8bd2e78e94c4043d0a7630637f966d15bf6",
            "da7c6a66bea564f3ffaf8c03a0b64ee2922dc9d4f4a000ee78a007eb4b9b3a84",
            "dbf1263cb74904fe77dcbbd7d0f2dbcf73344cba8cf9b3ee242d8832d2ef1b20",
        ],
        "bochk.go.platinum": [
            "13c4e11e7495b12d51fa4473e2e0a6ca68645c1ae7e52856cf41c1c1009fc5b5",
            "1c3539278cb132b7c5261576ba307a49efd0e05706234d8a0f857b7841400dfd",
            "da7c6a66bea564f3ffaf8c03a0b64ee2922dc9d4f4a000ee78a007eb4b9b3a84",
            "dbf1263cb74904fe77dcbbd7d0f2dbcf73344cba8cf9b3ee242d8832d2ef1b20",
        ],
        "bochk.mastercard.debit": [
            "00e10219bc98290084f2c2e98daf407e357d41b05f2a016fbda5d98eeb2b4ee1",
            "a47c051b9d88c6d5d8f250af11fef22bf8379307f5681ce72cbb463f5bad69d3",
        ],
        "bocom.gba.unionpay.diamond": [
            "5da3c7bd6858129ecf245eae368796e8dcd302ef83b130ce3f8012fa012abda1",
            "832a860fc1ad91b7d17df8549073354d6051c59956c3073d3c2cd1d29288dae0",
            "d0a49568b7ee8b094f5d411b7361368f58bea00466c18179fb84bb928126bbc5",
        ],
        "bocom.go-goal.visa.platinum": [
            "a11586355c4a1316b009a2cf815b02991e2bdc945009aa6e9923b32b5413ce58",
            "d7d1672d2e41d9939bd1f46aac0f7c8040b2f0abc8fcb6d57484a080a08898a1",
        ],
        "cncbi.gba.dual": [
            "a8523bbca03f4d31d1a4487c95db0e2504dddda2db654bf7824d62e5bdb567c8",
            "c5d9c159c06de9d4591d0b0845a177bb699d730e35f4fbd0feae94db75c845ed",
        ],
        "cncbi.multi-currency.debit": [
            "844955d8805488c177cf229a5cf7f04324f9605d67f299ba5f7b6fcf722d53e6",
            "93d08898c89ee0e7b081b5cdd1363b8dd624aca32731e4cc4a2836dc4bcec911",
        ],
        "hsbc.mastercard.debit": [
            "28a4fe138946563b56ba986211a8199acd6d35a4286af3caf757ec216b7409b7",
            "32ccf40d121ae97d7efddf77617a53a5ce6e5430d765d8d308bafceab74caf1b",
            "612a99872ddc14c46538d2a800d053d51049dd696cad292e5c32aa9a409cb6c4",
        ],
        "hsbc.pulse.unionpay.diamond": [
            "10489c8b64340dfd89e722f0e4d99af27579909b1f7a01c3f3438c13c98b4471",
            "801f2cdede369eff3117cf9d9097464a33a7d8331d8f0c07d70357308b362eaa",
        ],
        "hsbc.student.visa.gold": [
            "95f115ce99127dc816056c30eef5c7dda355b50665f1d512a3b78e88f4d65cf2",
            "c468c626609b3558cb4d32cd81e4e85c6b20ca474ccc66bd4b95ae37a622915c",
            "e162de651561e7db0a1bf98df89e36097704d2e896524ffe456610246254ebe6",
        ],
    ]
}
