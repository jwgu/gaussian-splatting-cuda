#define STB_IMAGE_IMPLEMENTATION
#include "camera_utils.cuh"
#include "stb_image.h"
#include <cmath>
#include <eigen3/Eigen/Dense>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>

Camera loadCam(CameraInfo& cam_info) {

    // ptyhon code
    //    return Camera(colmap_id=cam_info.uid, R=cam_info.R, T=cam_info.T,
    //                   FoVx=cam_info.FovX, FoVy=cam_info.FovY,
    //                   image=gt_image, gt_alpha_mask=loaded_mask,
    //                   image_name=cam_info.image_name, uid=id)

    return Camera(cam_info._camera_model);
}

void dump_JSON(const std::filesystem::path& file_path, const nlohmann::json& json_data) {
    std::ofstream file(file_path.string());
    if (file.is_open()) {
        file << json_data.dump(4); // Write the JSON data with indentation of 4 spaces
        file.close();
    } else {
        throw std::runtime_error("Could not open file " + file_path.string());
    }
}

// serialize camera to json
nlohmann::json Dump_camera_to_JSON(Camera cam) {

    Eigen::Matrix4d Rt = Eigen::Matrix4d::Zero();
    Rt.block<3, 3>(0, 0) = cam._R.transpose();
    Rt.block<3, 1>(0, 3) = cam._T;
    Rt(3, 3) = 1.0;

    Eigen::Matrix4d W2C = Rt.inverse();
    Eigen::Vector3d pos = W2C.block<3, 1>(0, 3);
    Eigen::Matrix3d rot = W2C.block<3, 3>(0, 0);
    std::vector<std::vector<double>> serializable_array_2d;
    for (int i = 0; i < rot.rows(); i++) {
        serializable_array_2d.push_back(std::vector<double>(rot.row(i).data(), rot.row(i).data() + rot.row(i).size()));
    }

    nlohmann::json camera_entry = {
        {"id", cam._camera_ID},
        {"img_name", cam._image_name},
        {"width", cam._width},
        {"height", cam._height},
        {"position", std::vector<double>(pos.data(), pos.data() + pos.size())},
        {"rotation", serializable_array_2d},
        {"fy", fov2focal(cam._fov_y, cam._height)},
        {"fx", fov2focal(cam._fov_x, cam._width)}};

    return camera_entry;
}

Eigen::Matrix4d getWorld2View(const Eigen::Matrix3d& R, const Eigen::Vector3d& t) {
    Eigen::Matrix4d Rt = Eigen::Matrix4d::Zero();
    Rt.block<3, 3>(0, 0) = R.transpose();
    Rt.block<3, 1>(0, 3) = t;
    Rt(3, 3) = 1.0;
    return Rt;
}

Eigen::Matrix4d getWorld2View2(const Eigen::Matrix3d& R, const Eigen::Vector3d& t,
                               const Eigen::Vector3d& translate /*= Eigen::Vector3d::Zero()*/, float scale /*= 1.0*/) {
    Eigen::Matrix4d Rt = Eigen::Matrix4d::Zero();
    Rt.block<3, 3>(0, 0) = R.transpose();
    Rt.block<3, 1>(0, 3) = t;
    Rt(3, 3) = 1.0;

    Eigen::Matrix4d C2W = Rt.inverse();
    Eigen::Vector3d cam_center = C2W.block<3, 1>(0, 3);
    cam_center = (cam_center + translate) * scale;
    C2W.block<3, 1>(0, 3) = cam_center;
    Rt = C2W.inverse();
    return Rt;
}

Eigen::Matrix4d getProjectionMatrix(double znear, double zfar, double fovX, double fovY) {
    double tanHalfFovY = std::tan((fovY / 2));
    double tanHalfFovX = std::tan((fovX / 2));

    double top = tanHalfFovY * znear;
    double bottom = -top;
    double right = tanHalfFovX * znear;
    double left = -right;

    Eigen::Matrix4d P = Eigen::Matrix4d::Zero();

    double z_sign = 1.0;

    P(0, 0) = 2.0 * znear / (right - left);
    P(1, 1) = 2.0 * znear / (top - bottom);
    P(0, 2) = (right + left) / (right - left);
    P(1, 2) = (top + bottom) / (top - bottom);
    P(3, 2) = z_sign;
    P(2, 2) = z_sign * zfar / (zfar - znear);
    P(2, 3) = -(zfar * znear) / (zfar - znear);
    return P;
}

double fov2focal(double fov, double pixels) {
    return pixels / (2 * std::tan(fov / 2));
}

double focal2fov(double focal, double pixels) {
    return 2 * std::atan(pixels / (2 * focal));
}

Eigen::Matrix3d qvec2rotmat(const Eigen::Quaterniond& qvec) {
    return qvec.normalized().toRotationMatrix();
}

Eigen::Quaterniond rotmat2qvec(const Eigen::Matrix3d& R) {
    Eigen::Quaterniond qvec(R);
    // the order of coefficients is different in python implementation.
    // Might be a bug here if data comes in wrong order! TODO: check
    if (qvec.w() < 0) {
        qvec.coeffs() *= -1;
    }
    return qvec;
}

unsigned char* read_image(std::filesystem::path image_path, int width, int height, int channels) {
    unsigned char* img = stbi_load(image_path.string().c_str(), &width, &height, &channels, 0);
    if (img == nullptr) {
        throw std::runtime_error("Could not load image: " + image_path.string());
    }

    return img;
}

void free_image(unsigned char* image) {
    stbi_image_free(image);
    image = nullptr;
}
