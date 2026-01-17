create database session15;
use session15;

create table users (
    user_id int auto_increment primary key,
    username varchar(50) not null unique,
    password varchar(255) not null,
    email varchar(100) not null unique,
    created_at datetime default (current_timestamp())
);

create table posts (
    post_id int auto_increment primary key,
    user_id int not null,
    content text not null,
    like_count int default 0,
    created_at datetime default (current_timestamp()),

    foreign key (user_id) references users(user_id)
);

create table comments (
    comment_id int auto_increment primary key,
    post_id int not null,
    user_id int not null,
    content text not null,
    created_at datetime default (current_timestamp()),

    foreign key (post_id) references posts(post_id),
    foreign key (user_id) references users(user_id)
);

create table likes (
    user_id int not null,
    post_id int not null,
    created_at datetime default (current_timestamp()),

    primary key (user_id, post_id),
    foreign key (user_id) references users(user_id),
    foreign key (post_id) references posts(post_id)
);

create table friends (
    user_id int not null,
    friend_id int not null,
    status enum('pending','accepted') default 'pending',
    created_at datetime default (current_timestamp()),

    primary key (user_id, friend_id),
    foreign key (user_id) references users(user_id),
    foreign key (friend_id) references users(user_id)
);

create table user_log (
    log_id int auto_increment primary key,
    user_id int,
    action varchar(255),
    log_time datetime default (current_timestamp())
);

create table post_log (
    log_id int auto_increment primary key,
    user_id int,
    post_id int,
    action varchar(255),
    log_time datetime default (current_timestamp())
);

delimiter //

-- Bài 1: Đăng ký thành viên
create procedure sp_register_user(
    p_username varchar(50),
    p_password varchar(255),
    p_email varchar(100)
)
begin
    declare exit handler for sqlexception
    begin
        rollback;
        resignal;
    end;

    start transaction;

        if exists (select 1 from users where username = p_username) then
            signal sqlstate '45000'
            set message_text = 'Username đã tồn tại';
        end if;

        if exists (select 1 from users where email = p_email) then
            signal sqlstate '45000'
            set message_text = 'Email đã tồn tại';
        end if;

        insert into users(username, password, email)
        values (p_username, p_password, p_email);

    commit;
end //

delimiter ;

delimiter //

create trigger tg_after_insert_user
after insert on users
for each row
begin
    insert into user_log(user_id, action)
    values (new.user_id, 'Đăng ký tài khoản');
end //

delimiter ;

-- Bài 2: Đăng bài viết
delimiter //

create procedure sp_create_post(
    p_user_id int,
    p_content text
)
begin
    if trim(p_content) = '' then
        signal sqlstate '45000'
        set message_text = 'Nội dung bài viết không hợp lệ';
    end if;

    insert into posts(user_id, content)
    values (p_user_id, p_content);
end //

delimiter ;

delimiter //

create trigger tg_after_insert_post
after insert on posts
for each row
begin
    insert into post_log(user_id, post_id, action)
    values (new.user_id, new.post_id, 'Tạo bài viết');
end //

delimiter ;

-- Like bài viết
delimiter //

create procedure sp_like_post(
    p_user_id int,
    p_post_id int
)
begin
    insert into likes(user_id, post_id)
    values (p_user_id, p_post_id);
end //

create procedure sp_unlike_post(
    p_user_id int,
    p_post_id int
)
begin
    delete from likes
    where user_id = p_user_id
      and post_id = p_post_id;
end //

delimiter ;

delimiter //

create trigger tg_after_like
after insert on likes
for each row
begin
    update posts
    set like_count = like_count + 1
    where post_id = new.post_id;

    insert into user_log(user_id, action)
    values (new.user_id, 'Đã thich bài viết');
end //

create trigger tg_after_unlike
after delete on likes
for each row
begin
    update posts
    set like_count = like_count - 1
    where post_id = old.post_id;

    insert into user_log(user_id, action)
    values (old.user_id, 'Đã bỏ viết bài viết');
end //

delimiter ;

-- Bài 4: Gửi lời mời kết bạn
delimiter //

create procedure sp_send_friend_request(
    p_user_id int,
    p_friend_id int
)
begin
    if p_user_id = p_friend_id then
        signal sqlstate '45000'
        set message_text = 'Không thể kết bạn với chính mình';
    end if;

    insert into friends(user_id, friend_id)
    values (p_user_id, p_friend_id);
end //

delimiter ;

-- Bài 5: Chấp nhận lời mời kết bạn
delimiter //

create procedure sp_accept_friend_request(
    p_user_id int,
    p_friend_id int
)
begin
    start transaction;

        update friends
        set status = 'accepted'
        where user_id = p_user_id
          and friend_id = p_friend_id;

        insert into friends(user_id, friend_id, status)
        values (p_friend_id, p_user_id, 'accepted')
        on duplicate key update status = 'accepted';

    commit;
end //

delimiter ;

-- Bài 6: Quản lý mối quan hệ bạn bè
delimiter //

create procedure sp_unfriend(
    p_user_id int,
    p_friend_id int
)
begin
    start transaction;

        delete from friends
        where (user_id = p_user_id and friend_id = p_friend_id)
           or (user_id = p_friend_id and friend_id = p_user_id);

    commit;
end //

delimiter ;

-- Bài 7: Xóa bài viết
delimiter //

create procedure sp_delete_post(
    p_post_id int,
    p_user_id int
)
begin
    declare owner_id int;

    start transaction;

        select user_id into owner_id
        from posts
        where post_id = p_post_id;

        if owner_id is null then
            rollback;
            signal sqlstate '45000'
            set message_text = 'Bài viết không tồn tại';
        end if;

        if owner_id <> p_user_id then
            rollback;
            signal sqlstate '45000'
            set message_text = 'Không có quyền xóa bài viết';
        end if;

        delete from likes where post_id = p_post_id;
        delete from comments where post_id = p_post_id;
        delete from posts where post_id = p_post_id;

    commit;
end //

delimiter ;

-- Bài 8: Xóa tài khoản người dùng
delimiter //

create procedure sp_delete_user(
    p_user_id int
)
begin
    start transaction;

        delete from posts where user_id = p_user_id;
        delete from comments where user_id = p_user_id;
        delete from likes where user_id = p_user_id;
        delete from friends where user_id = p_user_id;
        delete from users where user_id = p_user_id;

    commit;
end //

delimiter ;\
-- DEMO
-- THêm user
call sp_register_user('an',  '123456', 'an@gmail.com');
call sp_register_user('binh','123456', 'binh@gmail.com');
call sp_register_user('chi', '123456', 'chi@gmail.com');
call sp_register_user('dung','123456', 'dung@gmail.com');

select * from users;
select * from user_log;

-- Thêm lỗi
call sp_register_user('an', 'abcdef', 'an2@gmail.com');
call sp_register_user('an2', 'abcdef', 'an@gmail.com');

-- Thêm bài viết
call sp_create_post(1, 'Hom nay troi dep');
call sp_create_post(1, 'Hoc MySQL stored procedure');
call sp_create_post(2, 'Bai viet dau tien cua Binh');
call sp_create_post(3, 'Xin chao moi nguoi');
call sp_create_post(4, 'Toi dang hoc trigger');

select * from posts;
select * from post_log;

-- THÊm lỗi
call sp_create_post(1, '   ');

-- Thích bài viết
call sp_like_post(2, 1);
call sp_like_post(3, 1);
call sp_like_post(4, 1);
call sp_like_post(1, 3);
call sp_like_post(3, 3);

select post_id, content, like_count from posts;
select * from likes;
select * from user_log;

-- Bỏ thích 
call sp_unlike_post(3, 1);
select post_id, like_count from posts where post_id = 1;

call sp_like_post(2, 1);

-- GỬi lời mời kết bạn
call sp_send_friend_request(1, 2);
call sp_send_friend_request(1, 3);
call sp_send_friend_request(2, 3);

select * from friends;
select * from user_log;

call sp_send_friend_request(1, 1);

-- CHấp nhận kết bạn
call sp_accept_friend_request(1, 2);
call sp_accept_friend_request(1, 3);

select * from friends
where (user_id = 1 and friend_id = 2) or (user_id = 2 and friend_id = 1);

-- Hủy ket bạn
call sp_unfriend(1, 2);

select * from friends
where user_id in (1,2);

call sp_unfriend(3, 3);

-- THêm like và cm vào bài viết cần xóa

call sp_like_post(2, 2);
call sp_like_post(3, 2);

insert into comments(post_id, user_id, content) values 
(2, 3, 'Bai viet hay'),
(2, 4, 'Dong y');

select * from posts where post_id = 2;
select * from likes where post_id = 2;
select * from comments where post_id = 2;
-- xóa bài viết
call sp_delete_post(2, 1);

select * from posts where post_id = 2;
select * from likes where post_id = 2;
select * from comments where post_id = 2;
select * from post_log;

call sp_delete_post(1, 3);

-- Xóa tài khoản
call sp_delete_user(4);

select * from users;
select * from posts where user_id = 4;
select * from likes where user_id = 4;
select * from friends where user_id = 4;
select * from user_log;
