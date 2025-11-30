class UserAccount {
    let name: String
    var admin_account: AdminAccount?

    init(name: String){
        self.name = name
        self.admin_account = nil
    }
}

class AdminAccount {
    unowned(unsafe) let user_account: UserAccount
    let permissions: UInt64

    init(user_account: UserAccount, permissions: UInt64){
        self.user_account = user_account
        self.permissions = permissions
    }
}

func test() -> AdminAccount {
    let myuser = UserAccount(name: "john")
    myuser.admin_account = AdminAccount(user_account: myuser, permissions: 1)
    let myadmin = myuser.admin_account!
    print(myadmin.permissions)
    print(myadmin.user_account.name)
    return myadmin
}

func test2() {
    let myadmin = test()
    print(myadmin.permissions)
    print(myadmin.user_account.name)
}

test2()
