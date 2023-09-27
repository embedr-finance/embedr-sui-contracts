module library::utils {
    use std::debug;
    use std::string::utf8;

    public fun logger<T>(title: vector<u8>, value: &T ) {
        debug::print(&utf8(title));
        debug::print(value);
    }
}